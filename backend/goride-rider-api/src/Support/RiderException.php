<?php

declare(strict_types=1);

namespace GoRideRider\Support;

use RuntimeException;

/**
 * Error de negocio con código estable y estado HTTP. El mensaje es
 * siempre en español y seguro de mostrar al pasajero.
 */
final class RiderException extends RuntimeException
{
    /** @var array<string, array{0:int,1:string}> */
    public const CATALOG = [
        'AUTH_TOKEN_MISSING'      => [401, 'Inicia sesión para continuar.'],
        'AUTH_INVALID_TOKEN'      => [401, 'Tu sesión no es válida. Inicia sesión de nuevo.'],
        'AUTH_TOKEN_EXPIRED'      => [401, 'Tu sesión expiró. Inicia sesión de nuevo.'],
        'AUTH_TOKEN_REVOKED'      => [401, 'Tu sesión ya no es válida. Inicia sesión de nuevo.'],
        'AUTH_USER_NOT_FOUND'     => [401, 'Tu sesión no es válida. Inicia sesión de nuevo.'],
        'AUTH_UNAVAILABLE'        => [503, 'El servicio de autenticación no está disponible.'],
        'VALIDATION_ERROR'        => [422, 'Revisa los datos enviados.'],
        'SAME_LOCATION'           => [422, 'El origen y el destino son demasiado cercanos.'],
        'ZONE_NOT_ALLOWED'        => [422, 'Esa ubicación está fuera de la zona de servicio.'],
        'ZONE_UNVERIFIABLE'       => [503, 'No pudimos verificar la zona de servicio. Intenta de nuevo.'],
        'ROUTE_UNAVAILABLE'       => [503, 'No pudimos calcular la ruta. Intenta de nuevo.'],
        'QUOTE_UNAVAILABLE'       => [503, 'No pudimos calcular el precio. Intenta de nuevo.'],
        'QUOTE_INVALID'           => [422, 'La cotización no es válida. Solicita una nueva.'],
        'QUOTE_EXPIRED'           => [409, 'La cotización venció. Solicita una nueva.'],
        'PRICE_CHANGED'           => [409, 'El precio cambió. Revisa la nueva cotización.'],
        'PAYMENT_NOT_COMPATIBLE'  => [409, 'El pago en efectivo no está disponible en este momento.'],
        'IDEMPOTENCY_REQUIRED'    => [422, 'Falta la clave de idempotencia.'],
        'REQUEST_IN_PROGRESS'     => [409, 'Tu solicitud ya se está procesando.'],
        'ACTIVE_TRIP_EXISTS'      => [409, 'Ya tienes un viaje en curso.'],
        'BOOKING_CREATION_FAILED' => [502, 'No pudimos crear tu solicitud. Intenta de nuevo.'],
        'CANCEL_FAILED'           => [502, 'No pudimos cancelar el viaje. Intenta de nuevo.'],
        'TRIP_NOT_FOUND'          => [404, 'No encontramos ese viaje.'],
        'TRIP_NOT_CANCELABLE'     => [409, 'Este viaje ya no se puede cancelar.'],
        'PLACES_UNAVAILABLE'      => [503, 'La búsqueda de direcciones no está disponible. Intenta de nuevo.'],
        'CHAT_TOKEN_UNAVAILABLE'  => [503, 'El chat no está disponible en este momento.'],
        'RATE_LIMITED'            => [429, 'Demasiados intentos. Espera un momento.'],
        'INTERNAL_ERROR'          => [500, 'Ocurrió un error interno. Intenta de nuevo.'],
    ];

    /** @var array<string,mixed> */
    private array $extra;

    /** @param array<string,mixed> $extra */
    public function __construct(string $code, array $extra = [], ?string $message = null)
    {
        $entry = self::CATALOG[$code] ?? self::CATALOG['INTERNAL_ERROR'];
        parent::__construct($message ?? $entry[1]);
        $this->code_ = isset(self::CATALOG[$code]) ? $code : 'INTERNAL_ERROR';
        $this->extra = $extra;
    }

    private string $code_ = 'INTERNAL_ERROR';

    public function errorCode(): string
    {
        return $this->code_;
    }

    public function httpStatus(): int
    {
        return self::CATALOG[$this->code_][0];
    }

    /** @return array<string,mixed> */
    public function extra(): array
    {
        return $this->extra;
    }
}
