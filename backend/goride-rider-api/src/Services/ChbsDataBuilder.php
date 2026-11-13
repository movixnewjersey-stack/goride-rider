<?php

declare(strict_types=1);

namespace GoRideRider\Services;

/**
 * Arma el arreglo $data equivalente al POST del formulario CHBS
 * (servicio 1 = Distancia, solo ida), ya en formato "estándar" que
 * CHBSBookingForm::goToStep() entrega a sendBooking(): fecha d-m-Y,
 * hora H:i, coordenadas como JSON {lat,lng,address,zip_code,country_code}.
 */
final class ChbsDataBuilder
{
    /**
     * @param array{lat:float,lng:float,address:string,zip_code:string,country_code:string} $pickup
     * @param array{lat:float,lng:float,address:string,zip_code:string,country_code:string} $dropoff
     * @param array<string,float> $metrics
     * @param array<string,string> $contact
     * @return array<string,mixed>
     */
    public static function build(
        int $formId,
        int $vehicleId,
        array $pickup,
        array $dropoff,
        int $adults,
        \DateTimeInterface $when,
        array $metrics = [],
        array $contact = [],
        string $comment = ''
    ): array {
        $enc = static fn(array $p): string => json_encode([
            'lat' => $p['lat'], 'lng' => $p['lng'], 'address' => $p['address'],
            'zip_code' => $p['zip_code'], 'country_code' => $p['country_code'],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        $data = [
            'booking_form_id' => $formId,
            'step' => 4,
            'service_type_id' => 1,
            'vehicle_id' => $vehicleId,
            'transfer_type_service_type_1' => 1,
            'pickup_date_service_type_1' => $when->format('d-m-Y'),
            'pickup_time_service_type_1' => $when->format('H:i'),
            'return_date_service_type_1' => null,
            'return_time_service_type_1' => null,
            'pickup_location_coordinate_service_type_1' => $enc($pickup),
            'dropoff_location_coordinate_service_type_1' => $enc($dropoff),
            'fixed_location_pickup_service_type_1' => -1,
            'fixed_location_dropoff_service_type_1' => -1,
            'waypoint_location_coordinate_service_type_1' => [],
            'waypoint_duration_service_type_1' => [],
            'extra_time_service_type_1' => 0,
            'passenger_adult_service_type_1' => $adults,
            'passenger_children_service_type_1' => 0,
            'booking_extra' => [],
            'payment_id' => 1, // Efectivo (CHBSPayment: 1 = Cash)
            'comment' => $comment,
            'client_billing_detail_enable' => 0,
            'client_contact_detail_first_name' => $contact['first_name'] ?? '',
            'client_contact_detail_last_name' => $contact['last_name'] ?? '',
            'client_contact_detail_email_address' => $contact['email'] ?? '',
            'client_contact_detail_phone_number' => $contact['phone'] ?? '',
        ];

        foreach ([
            'distance_map', 'duration_map', 'distance_sum', 'duration_sum',
            'base_location_distance', 'base_location_return_distance',
            'base_location_duration', 'base_location_return_duration',
        ] as $k) {
            $data[$k] = $metrics[$k] ?? 0;
        }

        return $data;
    }
}
