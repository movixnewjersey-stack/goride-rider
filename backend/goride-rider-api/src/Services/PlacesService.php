<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\Geo;
use GoRideRider\Support\RiderException;

/**
 * Búsqueda de direcciones a través del servidor: la llave de Google
 * configurada en CHBS NUNCA sale del servidor ni viaja a la app.
 * Usa los servicios web de Google (Places Autocomplete/Details y Geocoding).
 */
final class PlacesService
{
    /** @var callable(string):?array */
    private $httpGet;
    /** @var callable():string */
    private $apiKey;

    /**
     * @param callable(string):?array $httpGet  recibe la URL completa y devuelve el JSON decodificado (o null)
     * @param callable():string $apiKey
     */
    public function __construct(callable $httpGet, callable $apiKey, private readonly ChbsGateway $chbs, private readonly Settings $settings)
    {
        $this->httpGet = $httpGet;
        $this->apiKey = $apiKey;
    }

    /** @return list<array{place_id:string,primary:string,secondary:string}> */
    public function autocomplete(string $q, ?float $lat, ?float $lng, string $session): array
    {
        $q = trim(preg_replace('/\s+/u', ' ', $q) ?? '');
        if (mb_strlen($q) < 3 || mb_strlen($q) > 100) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'q'], 'Escribe al menos 3 letras.');
        }
        $params = ['input' => $q, 'language' => 'es', 'sessiontoken' => $this->session($session)];
        $countries = $this->countries();
        if ($countries !== []) {
            $params['components'] = implode('|', array_map(static fn($c) => 'country:' . strtolower($c), array_slice($countries, 0, 5)));
        }
        if ($lat !== null && $lng !== null && Geo::validLat($lat) && Geo::validLng($lng)) {
            $params['location'] = $lat . ',' . $lng;
            $params['radius'] = '50000';
        }
        $json = $this->call('place/autocomplete', $params);
        $out = [];
        foreach ((array) ($json['predictions'] ?? []) as $p) {
            if (empty($p['place_id'])) {
                continue;
            }
            $fmt = (array) ($p['structured_formatting'] ?? []);
            $out[] = [
                'place_id' => (string) $p['place_id'],
                'primary' => (string) ($fmt['main_text'] ?? $p['description'] ?? ''),
                'secondary' => (string) ($fmt['secondary_text'] ?? ''),
            ];
        }

        return array_slice($out, 0, 8);
    }

    /** @return array{place_id:string,lat:float,lng:float,address:string,zip_code:string,country_code:string} */
    public function details(string $placeId, string $session): array
    {
        if (!preg_match('/^[A-Za-z0-9_-]{10,200}$/', $placeId)) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'place_id']);
        }
        $json = $this->call('place/details', [
            'place_id' => $placeId, 'language' => 'es', 'sessiontoken' => $this->session($session),
            'fields' => 'place_id,geometry/location,formatted_address,address_component',
        ]);
        $r = (array) ($json['result'] ?? []);

        return $this->shape($r, $placeId);
    }

    /** @return array{place_id:string,lat:float,lng:float,address:string,zip_code:string,country_code:string} */
    public function reverse(float $lat, float $lng): array
    {
        if (!Geo::validLat($lat) || !Geo::validLng($lng)) {
            throw new RiderException('VALIDATION_ERROR', ['field' => 'lat,lng']);
        }
        $json = $this->call('geocode', ['latlng' => round($lat, 6) . ',' . round($lng, 6), 'language' => 'es']);
        $first = ((array) ($json['results'] ?? []))[0] ?? null;
        if (!is_array($first)) {
            throw new RiderException('PLACES_UNAVAILABLE');
        }
        $first['geometry']['location'] = ['lat' => $lat, 'lng' => $lng];

        return $this->shape($first, (string) ($first['place_id'] ?? ''));
    }

    /** @param array<string,mixed> $r @return array{place_id:string,lat:float,lng:float,address:string,zip_code:string,country_code:string} */
    private function shape(array $r, string $placeId): array
    {
        $loc = $r['geometry']['location'] ?? null;
        if (!is_array($loc) || !Geo::validLat($loc['lat'] ?? null) || !Geo::validLng($loc['lng'] ?? null)) {
            throw new RiderException('PLACES_UNAVAILABLE');
        }
        $zip = '';
        $country = '';
        foreach ((array) ($r['address_components'] ?? []) as $c) {
            $types = (array) ($c['types'] ?? []);
            if (in_array('postal_code', $types, true)) {
                $zip = (string) ($c['long_name'] ?? '');
            }
            if (in_array('country', $types, true)) {
                $country = strtoupper((string) ($c['short_name'] ?? ''));
            }
        }

        return [
            'place_id' => $placeId,
            'lat' => round((float) $loc['lat'], 7),
            'lng' => round((float) $loc['lng'], 7),
            'address' => mb_substr((string) ($r['formatted_address'] ?? ''), 0, 255),
            'zip_code' => $zip,
            'country_code' => $country,
        ];
    }

    /** @param array<string,string> $params @return array<string,mixed> */
    private function call(string $path, array $params): array
    {
        $key = ($this->apiKey)();
        if ($key === '') {
            throw new RiderException('PLACES_UNAVAILABLE', ['reason' => 'api_key_missing']);
        }
        $url = 'https://maps.googleapis.com/maps/api/' . $path . '/json?' . http_build_query($params + ['key' => $key]);
        $json = ($this->httpGet)($url);
        $status = is_array($json) ? (string) ($json['status'] ?? '') : '';
        if (!in_array($status, ['OK', 'ZERO_RESULTS'], true)) {
            throw new RiderException('PLACES_UNAVAILABLE', ['reason' => 'google_status_' . ($status ?: 'no_response')]);
        }

        return $json;
    }

    private function session(string $s): string
    {
        return preg_match('/^[A-Za-z0-9_-]{8,64}$/', $s) ? $s : bin2hex(random_bytes(8));
    }

    /** @return list<string> países ISO-2 permitidos por la zona del formulario (para sesgar la búsqueda) */
    private function countries(): array
    {
        $form = $this->chbs->form($this->settings->bookingFormId());
        if ($form === null) {
            return [];
        }
        $z = $this->chbs->zone($form);
        $set = [];
        foreach (['pickup', 'dropoff'] as $k) {
            if (!empty($z[$k]['enabled'])) {
                foreach ((array) $z[$k]['countries'] as $c) {
                    $set[strtoupper((string) $c)] = true;
                }
            }
        }

        return array_keys($set);
    }
}
