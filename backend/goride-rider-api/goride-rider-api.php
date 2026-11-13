<?php
/**
 * Plugin Name: GoRide Rider API
 * Description: API segura para la app nativa de pasajeros (cotización, reserva, viaje activo, conductor, chat-token y cancelación). Independiente de goride-api, goride-live y goride-dispatch: no los modifica.
 * Version: 1.0.0
 * Requires PHP: 8.1
 * Author: GoRide
 *
 * Dependencias en tiempo de ejecución (solo lectura / reutilización):
 *  - goride-api   : AuthMiddleware (login Bearer v2)
 *  - goride-live  : goride_get_or_create_token(), POST /goride/v1/cancel
 *  - Chauffeur Booking System (CHBS)
 * Desactivar este plugin revierte el cambio por completo: no crea tablas ni opciones permanentes.
 */

if (!defined('ABSPATH')) {
    exit;
}

define('GORIDE_RIDER_API_VERSION', '1.0.0');
define('GORIDE_RIDER_API_DIR', __DIR__);

foreach ([
    'Support/RiderException', 'Support/Geo', 'Support/QuoteToken', 'Support/TripState',
    'Services/ChbsGateway', 'Services/ChbsGatewayLive', 'Services/Settings', 'Services/ZoneGuard',
    'Services/ChbsDataBuilder', 'Services/TripReader', 'Services/QuoteService', 'Services/BookingService',
    'Services/CancelService', 'Services/PlacesService', 'Services/RiderAuth', 'Rest/RiderController',
] as $goride_rider_file) {
    require_once __DIR__ . '/src/' . $goride_rider_file . '.php';
}
unset($goride_rider_file);

add_action('rest_api_init', static function (): void {
    $settings = new \GoRideRider\Services\Settings();
    $chbs = new \GoRideRider\Services\ChbsGatewayLive();
    $tokens = new \GoRideRider\Support\QuoteToken($settings->secret(), $settings->quoteTtlSeconds());
    $zones = new \GoRideRider\Services\ZoneGuard($chbs);
    $reader = new \GoRideRider\Services\TripReader(static fn(int $id): ?float => $chbs->bookingTotal($id));

    $contact = static function (int $userId): array {
        $u = get_userdata($userId);
        if (!$u) {
            return [];
        }
        $phone = (string) get_user_meta($userId, 'phone', true);
        if ($phone === '') {
            $phone = (string) get_user_meta($userId, 'billing_phone', true);
        }
        $first = (string) get_user_meta($userId, 'first_name', true);
        $last = (string) get_user_meta($userId, 'last_name', true);

        return [
            'first_name' => trim($first) !== '' ? $first : (string) $u->display_name,
            'last_name'  => trim($last) !== '' ? $last : '-',
            'email'      => (string) $u->user_email,
            'phone'      => $phone,
        ];
    };

    // Cancelación: reutiliza EXACTAMENTE la ruta existente POST /goride/v1/cancel (misma lógica y hooks).
    $cancelExecutor = static function (int $bookingId, string $clientToken): bool {
        $req = new \WP_REST_Request('POST', '/goride/v1/cancel');
        $req->set_body_params(['booking_id' => $bookingId, 'token' => $clientToken]);
        $res = rest_do_request($req);
        $data = $res->get_data();

        return !$res->is_error() && is_array($data) && !empty($data['ok']);
    };

    (new \GoRideRider\Rest\RiderController(
        new \GoRideRider\Services\RiderAuth(),
        new \GoRideRider\Services\QuoteService($chbs, $settings, $tokens, $zones),
        new \GoRideRider\Services\BookingService($chbs, $settings, $tokens, $zones, $reader, $contact),
        new \GoRideRider\Services\CancelService($reader, $cancelExecutor),
        $reader,
        $chbs,
        $settings,
        new \GoRideRider\Services\PlacesService(
            static function (string $url): ?array {
                $res = wp_remote_get($url, ['timeout' => 8]);
                if (is_wp_error($res) || (int) wp_remote_retrieve_response_code($res) !== 200) {
                    return null;
                }
                $j = json_decode((string) wp_remote_retrieve_body($res), true);

                return is_array($j) ? $j : null;
            },
            static fn(): string => class_exists('CHBSOption') ? (string) \CHBSOption::getOption('google_map_api_key') : '',
            $chbs,
            $settings
        )
    ))->register();
});
