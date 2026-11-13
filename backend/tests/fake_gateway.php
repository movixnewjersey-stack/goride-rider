<?php
declare(strict_types=1);

use GoRideRider\Services\ChbsGateway;
use GoRideRider\Support\RiderException;

class FakeGateway implements ChbsGateway
{
    public int $createCalls = 0;
    public int $routeCalls = 0;
    public bool $cash = true;
    public bool $createFails = false;
    public bool $noisy = false;
    public float $gross = 18.45;
    public ?array $vehicle = ['id' => 77, 'name' => 'Automóvil'];
    public array $zone = ['enabled' => true, 'relation' => 1,
        'pickup' => ['enabled' => true, 'countries' => ['US'], 'area' => '', 'area_lat' => null, 'area_lng' => null, 'radius_km' => 0],
        'dropoff' => ['enabled' => true, 'countries' => ['US'], 'area' => '', 'area_lat' => null, 'area_lng' => null, 'radius_km' => 0]];
    public ?string $country = 'US';
    public array $form = ['meta' => ['service_type_id' => [1], 'location_fixed_pickup_service_type_1' => [], 'location_fixed_dropoff_service_type_1' => [], 'payment_id' => [1]], 'dictionary' => []];
    public ?array $lastCreateData = null;

    public function form(int $formId): ?array { return $formId === 20994 ? $this->form : null; }
    public function cashCompatible(array $form): bool { return $this->cash; }
    public function vehicle(array $form, ?int $c): ?array { return $this->vehicle; }
    public function zone(array $form): array { return $this->zone; }
    public function countryOf(float $lat, float $lng): ?string { return $this->country; }
    public function route(array $form, array $data): array
    {
        $this->routeCalls++;
        if ($this->noisy) { echo "Warning: legacy notice\n"; }
        return ['distance_map' => 12.3, 'duration_map' => 25.0, 'distance_sum' => 12.3, 'duration_sum' => 25.0,
            'base_location_distance' => 0.0, 'base_location_return_distance' => 0.0, 'base_location_duration' => 0.0, 'base_location_return_duration' => 0.0];
    }
    public function price(array $form, array $data): array { return ['gross' => $this->gross, 'net' => $this->gross, 'currency' => 'USD', 'formatted' => '$' . number_format($this->gross, 2)]; }
    public function create(array $form, array $data, int $userId): int|false
    {
        $this->createCalls++;
        $this->lastCreateData = $data;
        if ($this->createFails) { return false; }
        return wp_test_make_booking(['chbs_user_id' => $userId, 'chbs_coordinate' => [
            ['lat' => 40.7357, 'lng' => -74.1724, 'address' => 'Newark, NJ'], ['lat' => 40.7128, 'lng' => -74.0060, 'address' => 'New York, NY']]]);
    }
    public function bookingTotal(int $bookingId): ?float { return $this->gross; }
}
