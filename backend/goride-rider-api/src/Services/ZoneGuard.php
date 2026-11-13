<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\Geo;
use GoRideRider\Support\RiderException;

/**
 * Aplica EN EL SERVIDOR la restricción "Driving Zone" que CHBS solo
 * aplica en el navegador (Google Places). Lee la configuración del
 * formulario; no define ni cambia ninguna zona.
 */
final class ZoneGuard
{
    public function __construct(private readonly ChbsGateway $chbs)
    {
    }

    /**
     * @param array<string,mixed> $form
     * @param array{lat:float,lng:float,country_code:string} $pickup
     * @param array{lat:float,lng:float,country_code:string} $dropoff
     */
    public function assertAllowed(array $form, array $pickup, array $dropoff): void
    {
        $zone = $this->chbs->zone($form);
        $pu = $this->check($zone['pickup'], $pickup);
        $do = $this->check($zone['dropoff'], $dropoff);

        $ok = ((int) $zone['relation'] === 2) ? ($pu || $do) : ($pu && $do);
        if (!$ok) {
            throw new RiderException('ZONE_NOT_ALLOWED');
        }
    }

    /**
     * @param array<string,mixed> $rule
     * @param array{lat:float,lng:float,country_code:string} $pt
     */
    private function check(array $rule, array $pt): bool
    {
        if (empty($rule['enabled'])) {
            return true;
        }
        $hasCountry = !empty($rule['countries']);
        $hasArea = is_numeric($rule['area_lat'] ?? null) && is_numeric($rule['area_lng'] ?? null)
            && (float) $rule['radius_km'] > 0 && trim((string) ($rule['area'] ?? '')) !== '';

        if ($hasCountry) {
            // El país NUNCA se toma del cliente: se geocodifica en el servidor.
            $country = $this->chbs->countryOf($pt['lat'], $pt['lng']);
            if ($country === null) {
                throw new RiderException('ZONE_UNVERIFIABLE');
            }
            if (!in_array($country, array_map('strtoupper', $rule['countries']), true)) {
                return false;
            }
        }
        if ($hasArea) {
            $d = Geo::distanceKm((float) $rule['area_lat'], (float) $rule['area_lng'], $pt['lat'], $pt['lng']);
            if ($d > (float) $rule['radius_km']) {
                return false;
            }
        }

        return true;
    }
}
