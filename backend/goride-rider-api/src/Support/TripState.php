<?php

declare(strict_types=1);

namespace GoRideRider\Support;

/**
 * Traduce los metadatos reales del backend GoRide a un estado único y
 * estable para la app de pasajeros. Función pura: no escribe nada.
 *
 * Metas reales (verificadas en goride-live.php / goride-dispatch.php /
 * goride-api de producción):
 *   _goride_live_status : '' | accepted | arrived_at_pickup | finished | cancelled_by_user
 *   _goride_offer_state : running | no_drivers | no_drivers_in_radius | dispatch_failed
 *                         | accepted | finished | cancelled_by_user
 */
final class TripState
{
    public const SEARCHING = 'searching';
    public const NO_DRIVERS = 'no_drivers';
    public const DRIVER_ASSIGNED = 'driver_assigned';
    public const DRIVER_ARRIVED = 'driver_arrived';
    public const FINISHED = 'finished';
    public const CANCELLED = 'cancelled';

    /** Pasado este tiempo buscando sin respuesta se informa "sin conductores" (solo lectura). */
    public const MAX_SEARCH_SECONDS = 1800;

    public static function resolve(string $live, string $offer, int $createdTs, int $nowTs): string
    {
        $live = strtolower(trim($live));
        $offer = strtolower(trim($offer));

        if (in_array($live, ['finished', 'completed'], true) || $offer === 'finished') {
            return self::FINISHED;
        }
        if (in_array($live, ['cancelled_by_user', 'cancelled'], true) || $offer === 'cancelled_by_user') {
            return self::CANCELLED;
        }
        if ($live === 'arrived_at_pickup') {
            return self::DRIVER_ARRIVED;
        }
        if ($live === 'accepted') {
            return self::DRIVER_ASSIGNED;
        }
        if (in_array($offer, ['no_drivers', 'dispatch_failed'], true)) {
            return self::NO_DRIVERS;
        }
        if ($createdTs > 0 && ($nowTs - $createdTs) > self::MAX_SEARCH_SECONDS) {
            return self::NO_DRIVERS;
        }

        return self::SEARCHING;
    }

    public static function isCancelable(string $state): bool
    {
        return in_array($state, [self::SEARCHING, self::NO_DRIVERS, self::DRIVER_ASSIGNED, self::DRIVER_ARRIVED], true);
    }

    /** ¿Impide pedir otro viaje? (no_drivers no bloquea: el pasajero puede reintentar). */
    public static function blocksNewRequest(string $state): bool
    {
        return in_array($state, [self::SEARCHING, self::DRIVER_ASSIGNED, self::DRIVER_ARRIVED], true);
    }

    public static function isTerminal(string $state): bool
    {
        return in_array($state, [self::FINISHED, self::CANCELLED], true);
    }

    public static function hasDriver(string $state): bool
    {
        return in_array($state, [self::DRIVER_ASSIGNED, self::DRIVER_ARRIVED], true);
    }
}
