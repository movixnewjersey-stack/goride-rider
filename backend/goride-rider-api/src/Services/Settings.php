<?php

declare(strict_types=1);

namespace GoRideRider\Services;

/**
 * Ajustes del módulo. Valores por defecto verificados en la captura del
 * formulario CHBS real ("Agendamiento USA", Booking Form ID 20994,
 * tipo de servicio Distance). Se pueden sobrescribir con constantes en
 * wp-config.php SIN editar el plugin:
 *   define('GORIDE_RIDER_BOOKING_FORM_ID', 20994);
 *   define('GORIDE_RIDER_VEHICLE_ID', 123);        // opcional
 *   define('GORIDE_RIDER_MAX_PASSENGERS', 4);
 */
final class Settings
{
    public function bookingFormId(): int
    {
        return defined('GORIDE_RIDER_BOOKING_FORM_ID') ? (int) GORIDE_RIDER_BOOKING_FORM_ID : 20994;
    }

    public function vehicleId(): ?int
    {
        return defined('GORIDE_RIDER_VEHICLE_ID') && (int) GORIDE_RIDER_VEHICLE_ID > 0 ? (int) GORIDE_RIDER_VEHICLE_ID : null;
    }

    public function maxPassengers(): int
    {
        return defined('GORIDE_RIDER_MAX_PASSENGERS') ? max(1, (int) GORIDE_RIDER_MAX_PASSENGERS) : 4;
    }

    /** Distancia mínima entre origen y destino (km). */
    public function minTripKm(): float
    {
        return 0.1;
    }

    /** Distancia máxima razonable entre origen y destino en línea recta (km). */
    public function maxTripKm(): float
    {
        return 300.0;
    }

    public function quoteTtlSeconds(): int
    {
        return 600;
    }

    public function secret(): string
    {
        return function_exists('wp_salt') ? wp_salt('auth') . '|goride-rider-quote' : '';
    }
}
