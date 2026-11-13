<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\Geo;
use GoRideRider\Support\QuoteToken;
use GoRideRider\Support\RiderException;

/**
 * Cotización: SOLO LECTURA. No crea reservas ni escribe en la base de
 * datos. Distancia, duración y precio los calcula el servidor con el
 * motor de CHBS; el cliente solo envía puntos y pasajeros.
 */
final class QuoteService
{
    public function __construct(
        private readonly ChbsGateway $chbs,
        private readonly Settings $settings,
        private readonly QuoteToken $tokens,
        private readonly ZoneGuard $zones
    ) {
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function quote(int $userId, array $input, ?int $now = null): array
    {
        $now ??= time();
        $pickup = Geo::normalizePoint($input['pickup'] ?? null, 'pickup');
        $dropoff = Geo::normalizePoint($input['dropoff'] ?? null, 'dropoff');
        $adults = $this->passengers($input['passengers'] ?? 1);

        if (isset($input['pickup_at']) && $input['pickup_at'] !== null && $input['pickup_at'] !== '') {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'pickup_at'], 'Por ahora solo se pueden pedir viajes inmediatos.');
        }

        $km = Geo::distanceKm($pickup['lat'], $pickup['lng'], $dropoff['lat'], $dropoff['lng']);
        if ($km < $this->settings->minTripKm()) {
            throw new RiderException('SAME_LOCATION');
        }
        if ($km > $this->settings->maxTripKm()) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'dropoff'], 'El destino está demasiado lejos.');
        }

        $form = $this->chbs->form($this->settings->bookingFormId());
        if ($form === null) {
            throw new RiderException('QUOTE_UNAVAILABLE', ['reason' => 'booking_form_missing']);
        }
        if (!$this->chbs->cashCompatible($form)) {
            throw new RiderException('PAYMENT_NOT_COMPATIBLE');
        }
        if (count((array) ($form['meta']['location_fixed_pickup_service_type_1'] ?? [])) > 0
            || count((array) ($form['meta']['location_fixed_dropoff_service_type_1'] ?? [])) > 0) {
            throw new RiderException('QUOTE_UNAVAILABLE', ['reason' => 'fixed_locations']);
        }
        if (!in_array(1, array_map('intval', (array) ($form['meta']['service_type_id'] ?? [])), true)) {
            throw new RiderException('QUOTE_UNAVAILABLE', ['reason' => 'service_type_distance_disabled']);
        }
        $vehicle = $this->chbs->vehicle($form, $this->settings->vehicleId());
        if ($vehicle === null) {
            throw new RiderException('QUOTE_UNAVAILABLE', ['reason' => 'vehicle_unresolved']);
        }

        $this->zones->assertAllowed($form, $pickup, $dropoff);

        $when = (new \DateTimeImmutable('@' . $now))->setTimezone(function_exists('wp_timezone') ? wp_timezone() : new \DateTimeZone('UTC'));
        $base = ChbsDataBuilder::build($this->settings->bookingFormId(), $vehicle['id'], $pickup, $dropoff, $adults, $when);
        $metrics = $this->chbs->route($form, $base);
        $data = ChbsDataBuilder::build($this->settings->bookingFormId(), $vehicle['id'], $pickup, $dropoff, $adults, $when, $metrics);
        $price = $this->chbs->price($form, $data);

        if ($price['gross'] <= 0) {
            throw new RiderException('QUOTE_UNAVAILABLE', ['reason' => 'zero_price']);
        }

        $payload = [
            'uid' => $userId,
            'form' => $this->settings->bookingFormId(),
            'veh' => $vehicle['id'],
            'pu' => $pickup,
            'do' => $dropoff,
            'pax' => $adults,
            'm' => $metrics,
            'gross' => round($price['gross'], 2),
            'cur' => $price['currency'],
        ];
        $token = $this->tokens->issue($payload, $now);

        return [
            'quote_id' => $token,
            'expires_at' => gmdate('c', $now + $this->settings->quoteTtlSeconds()),
            'price' => [
                'total' => round($price['gross'], 2),
                'currency' => $price['currency'],
                'formatted' => $price['formatted'],
            ],
            'distance_km' => $metrics['distance_map'],
            'duration_min' => (int) round($metrics['duration_map']),
            'passengers' => $adults,
            'vehicle_name' => $vehicle['name'],
            'payment_method' => 'cash',
            'pickup' => $pickup,
            'dropoff' => $dropoff,
        ];
    }

    private function passengers(mixed $v): int
    {
        if (!is_numeric($v) || (int) $v != $v || (int) $v < 1 || (int) $v > $this->settings->maxPassengers()) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'passengers'], 'Cantidad de pasajeros inválida.');
        }

        return (int) $v;
    }
}
