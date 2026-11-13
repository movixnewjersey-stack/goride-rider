<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\RiderException;

/**
 * Implementación real sobre CHBS 8.x. Basada en la lectura de:
 *  - CHBSBookingForm::checkBookingForm / createSummaryPriceElement
 *  - CHBSBooking::calculatePrice / sendBooking / createBilling
 *  - CHBSGoogleMapAPI::computeRoutes / validateBookingFormData
 * NO ejecutada contra un WordPress real en el entorno de desarrollo.
 */
final class ChbsGatewayLive implements ChbsGateway
{
    public function form(int $formId): ?array
    {
        if (!class_exists('CHBSBookingForm')) {
            return null;
        }
        $builder = new \CHBSBookingForm();
        $form = $builder->checkBookingForm($formId, null, false);

        return is_array($form) ? $form : null;
    }

    public function cashCompatible(array $form): bool
    {
        $enabled = (array) ($form['meta']['payment_id'] ?? []);
        if (!in_array(1, array_map('intval', $enabled), true)) {
            return false;
        }
        if (class_exists('CHBSWooCommerce')) {
            $woo = new \CHBSWooCommerce();
            if ($woo->isEnable($form['meta']) || $woo->isAddToCartEnable($form)) {
                return false;
            }
        }

        return true;
    }

    public function vehicle(array $form, ?int $configuredId): ?array
    {
        $dict = (array) ($form['dictionary']['vehicle'] ?? []);
        if ($configuredId !== null && $configuredId > 0) {
            if (!isset($dict[$configuredId])) {
                return null;
            }
            $v = $dict[$configuredId];
        } elseif (count($dict) === 1) {
            $v = reset($dict);
        } else {
            return null;
        }
        $id = (int) ($v['post']->ID ?? 0);

        return $id > 0 ? ['id' => $id, 'name' => (string) ($v['post']->post_title ?? '')] : null;
    }

    public function zone(array $form): array
    {
        $m = $form['meta'];
        $area = static fn(string $f): array => [
            'enabled' => (int) ($m['driving_zone_restriction_' . $f . '_location_enable'] ?? 0) === 1,
            'countries' => array_values(array_filter(
                array_map('strval', (array) ($m['driving_zone_restriction_' . $f . '_location_country'] ?? [])),
                static fn($c) => $c !== '-1' && $c !== ''
            )),
            'area' => trim((string) ($m['driving_zone_restriction_' . $f . '_location_area'] ?? '')),
            'area_lat' => $m['driving_zone_restriction_' . $f . '_location_area_coordinate_lat'] ?? null,
            'area_lng' => $m['driving_zone_restriction_' . $f . '_location_area_coordinate_lng'] ?? null,
            'radius_km' => (float) ($m['driving_zone_restriction_' . $f . '_location_area_radius'] ?? 0),
        ];

        return [
            'enabled'  => true,
            'relation' => (int) ($m['driving_zone_restriction_location_field_relation_type'] ?? 1),
            'pickup'   => $area('pickup'),
            'dropoff'  => $area('dropoff'),
        ];
    }

    public function countryOf(float $lat, float $lng): ?string
    {
        if (!class_exists('CHBSGeoCoding')) {
            return null;
        }
        $code = (new \CHBSGeoCoding())->getCountryCode($lat, $lng);

        return is_string($code) && $code !== '' ? strtoupper($code) : null;
    }

    public function route(array $form, array $data): array
    {
        if (!class_exists('CHBSGoogleMapAPI')) {
            throw new RiderException('ROUTE_UNAVAILABLE');
        }
        $api = new \CHBSGoogleMapAPI();
        $r1 = $api->computeRoutes($form, $data, 1);
        if ($r1 === -1 || !is_object($r1) || empty($r1->routes[0])) {
            throw new RiderException('ROUTE_UNAVAILABLE');
        }
        // Mismo redondeo que CHBSGoogleMapAPI::validateBookingFormData().
        $distance = round(((int) $r1->routes[0]->distanceMeters) / 1000, 1);
        $duration = ceil(((int) $r1->routes[0]->duration) / 60);
        $rounding = (float) ($form['meta']['ride_time_rounding'] ?? 0);
        if ($rounding > 0.0) {
            $duration = ceil($duration / $rounding) * $rounding;
        }
        $duration *= (float) ($form['meta']['ride_time_multiplier'] ?? 1);

        $out = [
            'distance_map' => $distance,
            'duration_map' => (float) $duration,
            // Servicio 1, solo ida (transfer_type 1): multiplicador 1, sin tiempo extra ni paradas.
            'distance_sum' => $distance,
            'duration_sum' => (float) $duration,
            'base_location_distance' => 0.0,
            'base_location_return_distance' => 0.0,
            'base_location_duration' => 0.0,
            'base_location_return_duration' => 0.0,
        ];

        $r2 = $api->computeRoutes($form, $data, 2);
        if ($r2 === -1) {
            throw new RiderException('ROUTE_UNAVAILABLE');
        }
        if ($r2 !== -2 && is_object($r2) && !empty($r2->routes[0])) {
            $out['base_location_distance'] = round(((int) $r2->routes[0]->distanceMeters) / 1000, 1);
            $out['base_location_duration'] = (float) ceil(((int) $r2->routes[0]->duration) / 60);
            $r3 = $api->computeRoutes($form, $data, 3);
            if ($r3 === -1) {
                throw new RiderException('ROUTE_UNAVAILABLE');
            }
            if ($r3 !== -2 && is_object($r3) && !empty($r3->routes[0])) {
                $out['base_location_return_distance'] = round(((int) $r3->routes[0]->distanceMeters) / 1000, 1);
                $out['base_location_return_duration'] = (float) ceil(((int) $r3->routes[0]->duration) / 60);
            }
        }

        return $out;
    }

    public function price(array $form, array $data): array
    {
        if (!class_exists('CHBSBooking')) {
            throw new RiderException('QUOTE_UNAVAILABLE');
        }
        $data['booking_form'] = $form;
        $booking = new \CHBSBooking();
        $price = $booking->calculatePrice($data, null, $form['meta']['booking_summary_hide_fee'] ?? false, true);
        if (!is_array($price) || !isset($price['total']['sum']['gross']['value'])) {
            throw new RiderException('QUOTE_UNAVAILABLE');
        }
        $currency = class_exists('CHBSCurrency') ? (string) \CHBSCurrency::getFormCurrency() : 'USD';
        $gross = (float) $price['total']['sum']['gross']['value'];
        if ($gross <= 0) {
            // Diagnóstico (solo lectura): qué devolvió CHBS cuando el precio es 0. Sin datos personales.
            error_log('[GORIDE-RIDER] zero_price pickup=' . ($data['pickup_date_service_type_1'] ?? '?') . ' ' . ($data['pickup_time_service_type_1'] ?? '?')
                . ' vehicle=' . ($data['vehicle_id'] ?? '?') . ' dist=' . ($data['distance_sum'] ?? '?') . ' dur=' . ($data['duration_sum'] ?? '?')
                . ' adults=' . ($data['passenger_adult_service_type_1'] ?? '?') . ' children=' . ($data['passenger_children_service_type_1'] ?? '?')
                . ' tz=' . (function_exists('wp_timezone_string') ? wp_timezone_string() : '?')
                . ' price=' . substr((string) wp_json_encode($price['total'] ?? $price), 0, 1500));
        }
        $net = (float) ($price['total']['sum']['net']['value'] ?? $gross);
        $formatted = class_exists('CHBSPrice')
            ? html_entity_decode(wp_strip_all_tags((string) \CHBSPrice::format($gross, $currency)))
            : number_format($gross, 2);

        return ['gross' => $gross, 'net' => $net, 'currency' => $currency, 'formatted' => $formatted];
    }

    public function create(array $form, array $data, int $userId): int|false
    {
        if (!class_exists('CHBSBooking')) {
            return false;
        }
        // CHBSBooking::sendBooking() lee el usuario de la sesión de WordPress
        // (CHBSUser::isSignIn); en REST con Bearer no hay sesión, así que se
        // fija el usuario SOLO durante la llamada y se restaura después.
        $previous = get_current_user_id();
        wp_set_current_user($userId);
        try {
            $booking = new \CHBSBooking();
            $id = $booking->sendBooking($data, $form);
        } finally {
            wp_set_current_user($previous);
        }

        return is_int($id) && $id > 0 ? $id : false;
    }

    public function bookingTotal(int $bookingId): ?float
    {
        if (!class_exists('CHBSBooking')) {
            return null;
        }
        try {
            $billing = (new \CHBSBooking())->createBilling($bookingId);

            return isset($billing['summary']['value_gross']) ? (float) $billing['summary']['value_gross'] : null;
        } catch (\Throwable $e) {
            return null;
        }
    }
}
