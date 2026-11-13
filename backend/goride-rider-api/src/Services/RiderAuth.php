<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\RiderException;

/**
 * Autenticación Bearer reutilizando el AuthMiddleware REAL de goride-api
 * (solo lectura de esa clase; no se modifica). Si goride-api no está
 * activo, falla cerrado con AUTH_UNAVAILABLE.
 */
final class RiderAuth
{
    /** @var null|callable(\WP_REST_Request):int */
    private $authenticator;

    /** @param null|callable(\WP_REST_Request):int $authenticator solo para pruebas */
    public function __construct(?callable $authenticator = null)
    {
        $this->authenticator = $authenticator;
    }

    public function userId(\WP_REST_Request $request): int
    {
        try {
            if ($this->authenticator !== null) {
                $id = ($this->authenticator)($request);
            } else {
                if (!class_exists('\\GoRide\\Api\\Middleware\\AuthMiddleware')) {
                    throw new RiderException('AUTH_UNAVAILABLE');
                }
                $id = \GoRide\Api\Middleware\AuthMiddleware::authenticate($request)->userId();
            }
        } catch (RiderException $e) {
            throw $e;
        } catch (\Throwable $e) {
            $code = $e->getMessage();
            throw new RiderException(isset(RiderException::CATALOG[$code]) && str_starts_with($code, 'AUTH_') ? $code : 'AUTH_INVALID_TOKEN');
        }
        if ((int) $id <= 0) {
            throw new RiderException('AUTH_INVALID_TOKEN');
        }

        return (int) $id;
    }
}
