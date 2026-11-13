<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\QuoteToken;
use GoRideRider\Support\RiderException;

/**
 * Creación segura de la reserva. Garantías:
 *  - cotización firmada por el servidor (precio/distancia no editables);
 *  - el precio se recalcula con el motor de CHBS y debe coincidir;
 *  - reserva ligada al usuario autenticado (meta _goride_user_id);
 *  - idempotente: misma clave => misma reserva (reintentos, doble toque,
 *    pérdida de conexión); candado atómico contra solicitudes simultáneas;
 *  - un solo viaje bloqueante por usuario.
 */
final class BookingService
{
    public const IDEM_META = '_goride_rider_idem';

    /** @var callable(int):array<string,string> */
    private $contactResolver;

    /** @param callable(int):array<string,string> $contactResolver */
    public function __construct(
        private readonly ChbsGateway $chbs,
        private readonly Settings $settings,
        private readonly QuoteToken $tokens,
        private readonly ZoneGuard $zones,
        private readonly TripReader $reader,
        callable $contactResolver
    ) {
        $this->contactResolver = $contactResolver;
    }

    /**
     * @param array<string,mixed> $input
     * @return array{trip:array<string,mixed>,replayed:bool}
     */
    public function create(int $userId, array $input, ?int $now = null): array
    {
        $now ??= time();
        $key = (string) ($input['idempotency_key'] ?? '');
        if ($key === '') {
            throw new RiderException('IDEMPOTENCY_REQUIRED');
        }
        if (!preg_match('/^[A-Za-z0-9_-]{8,64}$/', $key)) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'idempotency_key']);
        }
        $quoteId = (string) ($input['quote_id'] ?? '');
        $idem = hash('sha256', $userId . '|' . $key);

        // 1) Reintento de una solicitud ya completada: misma reserva.
        $existing = $this->findByIdem($idem, $userId);
        if ($existing !== null) {
            return ['trip' => $this->reader->toArray($existing, $userId), 'replayed' => true];
        }

        // 2) Candados atómicos: por clave y por usuario.
        $locks = [];
        try {
            $locks[] = $this->acquire('goride_rider_lk_' . substr($idem, 0, 40), $now);
            $locks[] = $this->acquire('goride_rider_uk_' . $userId, $now);

            // Doble verificación tras tomar el candado.
            $existing = $this->findByIdem($idem, $userId);
            if ($existing !== null) {
                return ['trip' => $this->reader->toArray($existing, $userId), 'replayed' => true];
            }

            $active = $this->reader->findActiveFor($userId, false);
            if ($active !== null) {
                throw new RiderException('ACTIVE_TRIP_EXISTS', ['trip' => $active]);
            }

            $q = $this->tokens->verify($quoteId, $userId, $now);

            $formId = $this->settings->bookingFormId();
            if ((int) $q['form'] !== $formId) {
                throw new RiderException('QUOTE_INVALID');
            }
            $form = $this->chbs->form($formId);
            if ($form === null) {
                throw new RiderException('BOOKING_CREATION_FAILED', ['reason' => 'booking_form_missing']);
            }
            if (!$this->chbs->cashCompatible($form)) {
                throw new RiderException('PAYMENT_NOT_COMPATIBLE');
            }
            $vehicle = $this->chbs->vehicle($form, $this->settings->vehicleId());
            if ($vehicle === null || $vehicle['id'] !== (int) $q['veh']) {
                throw new RiderException('QUOTE_INVALID');
            }
            $this->zones->assertAllowed($form, $q['pu'], $q['do']);

            $when = (new \DateTimeImmutable('@' . $now))->setTimezone(function_exists('wp_timezone') ? wp_timezone() : new \DateTimeZone('UTC'));
            $contact = ($this->contactResolver)($userId);
            foreach (['first_name', 'last_name', 'email', 'phone'] as $field) {
                if (trim((string) ($contact[$field] ?? '')) === '') {
                    throw new RiderException('VALIDATION_ERROR', ['field' => $field], 'Completa tu ' . ($field === 'phone' ? 'teléfono' : ($field === 'email' ? 'correo' : 'nombre')) . ' en tu perfil para pedir un viaje.');
                }
            }
            $comment = mb_substr(trim(preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', (string) ($input['comment'] ?? ''))), 0, 200);

            $data = ChbsDataBuilder::build($formId, $vehicle['id'], $q['pu'], $q['do'], (int) $q['pax'], $when, (array) $q['m'], $contact, $comment);

            // El precio se recalcula en el servidor con las métricas firmadas.
            $fresh = $this->chbs->price($form, $data);
            if (abs($fresh['gross'] - (float) $q['gross']) > 0.005) {
                throw new RiderException('PRICE_CHANGED', ['price' => [
                    'total' => round($fresh['gross'], 2), 'currency' => $fresh['currency'], 'formatted' => $fresh['formatted'],
                ], 'previous_total' => (float) $q['gross']]);
            }

            $id = $this->chbs->create($form, $data, $userId);
            if ($id === false) {
                throw new RiderException('BOOKING_CREATION_FAILED');
            }

            update_post_meta($id, TripReader::OWNER_META, $userId);
            update_post_meta($id, TripReader::CREATED_VIA_META, 'rider_app');
            update_post_meta($id, self::IDEM_META, $idem);
            update_post_meta($id, '_goride_rider_quoted_gross', (string) $q['gross']);
            if (function_exists('goride_get_or_create_token')) {
                goride_get_or_create_token($id, 'client');
            }

            $trip = $this->reader->toArray($id, $userId);
            $trip['price_matches_quote'] = isset($trip['price']['total']) ? abs((float) $trip['price']['total'] - (float) $q['gross']) <= 0.01 : null;

            return ['trip' => $trip, 'replayed' => false];
        } finally {
            foreach ($locks as $name) {
                if ($name !== null) {
                    delete_option($name);
                }
            }
        }
    }

    private function findByIdem(string $idem, int $userId): ?int
    {
        $ids = get_posts([
            'post_type' => 'chbs_booking', 'post_status' => 'any', 'numberposts' => 1, 'fields' => 'ids',
            'suppress_filters' => true,
            'meta_query' => [
                'relation' => 'AND',
                ['key' => self::IDEM_META, 'value' => $idem, 'compare' => '='],
                ['key' => TripReader::OWNER_META, 'value' => (string) $userId, 'compare' => '='],
            ],
        ]);

        return !empty($ids) ? (int) $ids[0] : null;
    }

    /** add_option es atómico (UNIQUE option_name). Candados viejos (>90 s) se liberan. */
    private function acquire(string $name, int $now): string
    {
        if (add_option($name, (string) $now, '', 'no')) {
            return $name;
        }
        $held = (int) get_option($name, 0);
        if ($held > 0 && ($now - $held) > 90) {
            delete_option($name);
            if (add_option($name, (string) $now, '', 'no')) {
                return $name;
            }
        }
        throw new RiderException('REQUEST_IN_PROGRESS');
    }
}
