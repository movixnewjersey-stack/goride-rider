<?php

declare(strict_types=1);

namespace GoRideRider\Services;

/**
 * Frontera con Chauffeur Booking System (CHBS). Toda llamada a clases
 * internas de CHBS pasa por aquí para poder probar el resto con un
 * doble de prueba y aislar el único punto frágil.
 */
interface ChbsGateway
{
    /** Configuración del formulario ($bookingForm de CHBS) o null si no existe. */
    public function form(int $formId): ?array;

    /** El pago en efectivo (payment_id=1) está habilitado y no lo intercepta WooCommerce. */
    public function cashCompatible(array $form): bool;

    /** @return null|array{id:int,name:string} vehículo a usar (config explícita o único del formulario) */
    public function vehicle(array $form, ?int $configuredId): ?array;

    /**
     * Restricción de zona de conducción del formulario (lectura pura).
     *
     * @return array{enabled:bool,relation:int,pickup:array,dropoff:array}
     */
    public function zone(array $form): array;

    /** Código de país ISO-2 del punto (geocodificación del servidor), o null. */
    public function countryOf(float $lat, float $lng): ?string;

    /**
     * Distancia/duración reales calculadas EN EL SERVIDOR (Google Routes API
     * con la llave configurada en CHBS). Nunca se aceptan del cliente.
     *
     * @param array<string,mixed> $data
     * @return array{distance_map:float,duration_map:float,distance_sum:float,duration_sum:float,base_location_distance:float,base_location_return_distance:float,base_location_duration:float,base_location_return_duration:float}
     */
    public function route(array $form, array $data): array;

    /**
     * Precio con el MISMO motor que usa el formulario web.
     *
     * @param array<string,mixed> $data
     * @return array{gross:float,net:float,currency:string,formatted:string}
     */
    public function price(array $form, array $data): array;

    /**
     * Crea la reserva con CHBSBooking::sendBooking(). Devuelve el ID o false.
     *
     * @param array<string,mixed> $data
     */
    public function create(array $form, array $data, int $userId): int|false;

    /** Total bruto guardado de una reserva ya creada (CHBSBooking::createBilling), o null. */
    public function bookingTotal(int $bookingId): ?float;
}
