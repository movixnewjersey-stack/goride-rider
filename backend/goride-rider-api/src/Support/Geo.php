<?php

declare(strict_types=1);

namespace GoRideRider\Support;

final class Geo
{
    public static function validLat(mixed $v): bool
    {
        return is_numeric($v) && (float) $v >= -90.0 && (float) $v <= 90.0 && !(is_float($v) && is_nan($v));
    }

    public static function validLng(mixed $v): bool
    {
        return is_numeric($v) && (float) $v >= -180.0 && (float) $v <= 180.0 && !(is_float($v) && is_nan($v));
    }

    /** Distancia en kilómetros (haversine). */
    public static function distanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $r = 6371.0088;
        $p1 = deg2rad($lat1);
        $p2 = deg2rad($lat2);
        $dp = deg2rad($lat2 - $lat1);
        $dl = deg2rad($lng2 - $lng1);
        $a = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;

        return 2 * $r * asin(min(1.0, sqrt($a)));
    }

    /**
     * Normaliza un punto {lat,lng,address?,zip_code?,country_code?}.
     *
     * @param mixed $p
     * @return array{lat:float,lng:float,address:string,zip_code:string,country_code:string}
     */
    public static function normalizePoint(mixed $p, string $field): array
    {
        if (!is_array($p) || !self::validLat($p['lat'] ?? null) || !self::validLng($p['lng'] ?? null)) {
            throw new RiderException('VALIDATION_ERROR', ['field' => $field], 'Ubicación inválida: ' . $field . '.');
        }
        $clean = static fn($v, int $max): string => mb_substr(trim(preg_replace('/[\x00-\x1F\x7F"\\\\]/u', '', (string) ($v ?? ''))), 0, $max);

        return [
            'lat'          => round((float) $p['lat'], 7),
            'lng'          => round((float) $p['lng'], 7),
            'address'      => $clean($p['address'] ?? '', 255),
            'zip_code'     => $clean($p['zip_code'] ?? '', 20),
            'country_code' => strtoupper($clean($p['country_code'] ?? '', 2)),
        ];
    }
}
