<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\TripState;

/**
 * Modelo de lectura de un viaje para el pasajero. SOLO LEE: no escribe
 * ninguna meta ni tabla. Propiedad estricta: _goride_user_id == usuario.
 */
class TripReader
{
    public const OWNER_META = '_goride_user_id';
    public const CREATED_VIA_META = '_goride_rider_created_via';

    /** @var null|callable(int):?float */
    private $priceResolver;

    /** @param null|callable(int):?float $priceResolver */
    public function __construct(?callable $priceResolver = null)
    {
        $this->priceResolver = $priceResolver;
    }

    public function exists(int $bookingId): bool
    {
        $post = get_post($bookingId);

        return is_object($post) && ($post->post_type ?? '') === 'chbs_booking';
    }

    public function isOwner(int $bookingId, int $userId): bool
    {
        if ($bookingId <= 0 || $userId <= 0 || !$this->exists($bookingId)) {
            return false;
        }

        return (int) get_post_meta($bookingId, self::OWNER_META, true) === $userId;
    }

    public function state(int $bookingId, ?int $nowTs = null): string
    {
        $post = get_post($bookingId);
        $created = is_object($post) ? (int) strtotime((string) ($post->post_date_gmt ?? '') . ' UTC') : 0;

        return TripState::resolve(
            (string) get_post_meta($bookingId, '_goride_live_status', true),
            (string) get_post_meta($bookingId, '_goride_offer_state', true),
            $created,
            $nowTs ?? time()
        );
    }

    /**
     * Viaje más reciente del usuario que bloquea nuevas solicitudes
     * (searching/driver_assigned/driver_arrived), o null.
     *
     * @return null|array<string,mixed>
     */
    public function findActiveFor(int $userId, bool $includeNoDrivers = true): ?array
    {
        if ($userId <= 0) {
            return null;
        }
        $ids = get_posts([
            'post_type'        => 'chbs_booking',
            'post_status'      => 'any',
            'numberposts'      => 8,
            'orderby'          => 'ID',
            'order'            => 'DESC',
            'fields'           => 'ids',
            'suppress_filters' => true,
            'meta_query'       => [[
                'key'     => self::OWNER_META,
                'value'   => (string) $userId,
                'compare' => '=',
            ]],
        ]);

        foreach ((array) $ids as $id) {
            $id = (int) $id;
            $state = $this->state($id);
            if (TripState::blocksNewRequest($state)) {
                return $this->toArray($id, $userId, true);
            }
            if ($includeNoDrivers && $state === TripState::NO_DRIVERS && $this->recent($id, 900)) {
                return $this->toArray($id, $userId, true);
            }
        }

        return null;
    }

    private function recent(int $bookingId, int $seconds): bool
    {
        $post = get_post($bookingId);
        $created = is_object($post) ? (int) strtotime((string) ($post->post_date_gmt ?? '') . ' UTC') : 0;

        return $created > 0 && (time() - $created) <= $seconds;
    }

    /** @return array<string,mixed> */
    public function toArray(int $bookingId, int $userId, bool $withLocation = true): array
    {
        $state = $this->state($bookingId);
        $coordinate = get_post_meta($bookingId, 'chbs_coordinate', true);
        $driverId = $this->driverId($bookingId, $state);

        return [
            'booking_id'     => $bookingId,
            'status'         => $state,
            'status_raw'     => [
                'live'  => (string) get_post_meta($bookingId, '_goride_live_status', true),
                'offer' => (string) get_post_meta($bookingId, '_goride_offer_state', true),
            ],
            'status_at'      => $this->nullIfEmpty((string) get_post_meta($bookingId, '_goride_live_status_at', true)),
            'pickup'         => $this->point($coordinate, 0),
            'dropoff'        => $this->point($coordinate, 1),
            'price'          => $this->price($bookingId),
            'payment_method' => 'cash',
            'vehicle_name'   => $this->nullIfEmpty((string) get_post_meta($bookingId, 'chbs_vehicle_name', true)),
            'driver'         => $driverId > 0 ? $this->driver($driverId) : null,
            'driver_location' => ($withLocation && TripState::hasDriver($state) && $driverId > 0)
                ? $this->location($bookingId, $driverId) : null,
            'can_cancel'     => TripState::isCancelable($state),
            'is_terminal'    => TripState::isTerminal($state),
            'server_time'    => gmdate('c'),
        ];
    }

    private function driverId(int $bookingId, string $state): int
    {
        $assigned = (int) get_post_meta($bookingId, '_goride_assigned_driver_id', true);
        if ($assigned > 0) {
            return $assigned;
        }
        if ($state === TripState::FINISHED || TripState::hasDriver($state)) {
            $d = (int) get_post_meta($bookingId, 'chbs_driver_id', true);

            return $d > 0 ? $d : 0;
        }

        return 0;
    }

    /** @return null|array<string,mixed> */
    public function driver(int $driverId): ?array
    {
        $post = get_post($driverId);
        if (!is_object($post) || ($post->post_type ?? '') !== 'chbs_driver') {
            return null;
        }
        $thumb = (int) get_post_meta($driverId, '_thumbnail_id', true);
        $photo = $thumb > 0 && function_exists('wp_get_attachment_url') ? wp_get_attachment_url($thumb) : false;
        $first = trim((string) get_post_meta($driverId, 'chbs_first_name', true));

        // Privacidad: solo nombre de pila y foto. NO se expone teléfono ni email.
        return [
            'id'         => $driverId,
            'first_name' => $first !== '' ? $first : 'Conductor',
            'photo_url'  => is_string($photo) && $photo !== '' ? $photo : null,
        ];
    }

    /** @return null|array<string,mixed> */
    public function location(int $bookingId, int $driverId): ?array
    {
        global $wpdb;
        if (!isset($wpdb) || !is_object($wpdb)) {
            return null;
        }
        $table = $wpdb->prefix . 'goride_locations';
        $row = $wpdb->get_row(
            $wpdb->prepare("SELECT lat, lng, accuracy, updated_at FROM $table WHERE booking_id=%d AND driver_id=%d LIMIT 1", $bookingId, $driverId),
            ARRAY_A
        );
        if (!is_array($row) || !isset($row['lat'], $row['lng'])) {
            return null;
        }
        $ts = 0;
        try {
            $ts = (new \DateTimeImmutable((string) $row['updated_at'], function_exists('wp_timezone') ? wp_timezone() : new \DateTimeZone('UTC')))->getTimestamp();
        } catch (\Throwable $e) {
            $ts = 0;
        }

        return [
            'lat'         => (float) $row['lat'],
            'lng'         => (float) $row['lng'],
            'accuracy_m'  => isset($row['accuracy']) ? (float) $row['accuracy'] : null,
            'updated_at'  => $ts > 0 ? gmdate('c', $ts) : null,
            'age_seconds' => $ts > 0 ? max(0, time() - $ts) : null,
        ];
    }

    /** @return null|array<string,mixed> */
    private function price(int $bookingId): ?array
    {
        $total = $this->priceResolver !== null ? ($this->priceResolver)($bookingId) : null;
        if ($total === null) {
            return null;
        }

        return ['total' => round($total, 2), 'currency' => (string) (get_post_meta($bookingId, 'chbs_currency_id', true) ?: 'USD')];
    }

    /** @return null|array{lat:?float,lng:?float,address:?string} */
    private function point(mixed $coordinate, int $i): ?array
    {
        if (!is_array($coordinate) || !isset($coordinate[$i]) || !is_array($coordinate[$i])) {
            return null;
        }
        $p = $coordinate[$i];

        return [
            'lat'     => isset($p['lat']) ? (float) $p['lat'] : null,
            'lng'     => isset($p['lng']) ? (float) $p['lng'] : null,
            'address' => isset($p['address']) ? (string) $p['address'] : null,
        ];
    }

    private function nullIfEmpty(string $v): ?string
    {
        return $v === '' ? null : $v;
    }
}
