<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\RiderException;
use GoRideRider\Support\TripState;

/**
 * Cancelación autorizada: propiedad estricta + validación de estados.
 * La escritura real la hace la ruta existente POST /goride/v1/cancel
 * (mismo efecto, mismos hooks, sin duplicar lógica) invocada de forma
 * interna con el token de cliente que solo conoce el servidor.
 */
final class CancelService
{
    /** @var callable(int,string):bool */
    private $executor;

    /** @param callable(int,string):bool $executor ejecuta la cancelación existente (bookingId, clientToken) */
    public function __construct(private readonly TripReader $reader, callable $executor)
    {
        $this->executor = $executor;
    }

    /** @return array{trip:array<string,mixed>,already_cancelled:bool} */
    public function cancel(int $userId, int $bookingId): array
    {
        // 404 tanto si no existe como si no es suyo: no revela existencia.
        if (!$this->reader->isOwner($bookingId, $userId)) {
            throw new RiderException('TRIP_NOT_FOUND');
        }
        $state = $this->reader->state($bookingId);

        if ($state === TripState::CANCELLED) {
            return ['trip' => $this->reader->toArray($bookingId, $userId, false), 'already_cancelled' => true];
        }
        if (!TripState::isCancelable($state)) {
            throw new RiderException('TRIP_NOT_CANCELABLE', ['status' => $state]);
        }

        $token = function_exists('goride_get_or_create_token') ? (string) goride_get_or_create_token($bookingId, 'client') : '';
        if ($token === '' || !($this->executor)($bookingId, $token)) {
            throw new RiderException('CANCEL_FAILED');
        }

        return ['trip' => $this->reader->toArray($bookingId, $userId, false), 'already_cancelled' => false];
    }
}
