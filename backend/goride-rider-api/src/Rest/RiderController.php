<?php

declare(strict_types=1);

namespace GoRideRider\Rest;

use GoRideRider\Services\BookingService;
use GoRideRider\Services\CancelService;
use GoRideRider\Services\ChbsGateway;
use GoRideRider\Services\PlacesService;
use GoRideRider\Services\QuoteService;
use GoRideRider\Services\RiderAuth;
use GoRideRider\Services\Settings;
use GoRideRider\Services\TripReader;
use GoRideRider\Support\RiderException;

final class RiderController
{
    public const NAMESPACE = 'goride-rider/v1';

    public function __construct(
        private readonly RiderAuth $auth,
        private readonly QuoteService $quotes,
        private readonly BookingService $bookings,
        private readonly CancelService $cancels,
        private readonly TripReader $reader,
        private readonly ChbsGateway $chbs,
        private readonly Settings $settings,
        private readonly ?PlacesService $places = null
    ) {
    }

    public function register(): void
    {
        $ns = self::NAMESPACE;
        $id = ['id' => ['validate_callback' => static fn($v) => ctype_digit((string) $v) && (int) $v > 0]];
        $routes = [
            ['/config', 'GET', 'config', []],
            ['/quotes', 'POST', 'quote', []],
            ['/bookings', 'POST', 'book', []],
            ['/places/autocomplete', 'GET', 'placesSearch', []],
            ['/places/details', 'GET', 'placesDetails', []],
            ['/places/reverse', 'GET', 'placesReverse', []],
            ['/trips/active', 'GET', 'active', []],
            ['/trips/(?P<id>\d+)', 'GET', 'trip', $id],
            ['/trips/(?P<id>\d+)/driver', 'GET', 'driver', $id],
            ['/trips/(?P<id>\d+)/chat-token', 'GET', 'chatToken', $id],
            ['/trips/(?P<id>\d+)/cancel', 'POST', 'cancel', $id],
        ];
        foreach ($routes as [$path, $method, $fn, $args]) {
            register_rest_route($ns, $path, [
                'methods' => $method,
                'callback' => fn(\WP_REST_Request $r) => $this->run($r, $fn),
                'permission_callback' => '__return_true', // la autenticación Bearer se aplica dentro de run()
                'args' => $args,
            ]);
        }
    }

    /** @return \WP_REST_Response */
    public function run(\WP_REST_Request $request, string $fn)
    {
        // CHBS es código legado: cualquier aviso PHP impreso no debe romper el JSON.
        ob_start();
        try {
            $userId = $this->auth->userId($request);
            $data = $this->{'do' . ucfirst($fn)}($userId, $request);
            $res = $this->ok($data['data'] ?? $data, (int) ($data['_status'] ?? 200), (string) ($data['_message'] ?? 'OK'));
        } catch (RiderException $e) {
            $res = $this->fail($e);
        } catch (\Throwable $e) {
            error_log('[GORIDE-RIDER] ' . get_class($e) . ': ' . $e->getMessage() . ' @' . basename($e->getFile()) . ':' . $e->getLine());
            $res = $this->fail(new RiderException('INTERNAL_ERROR'));
        } finally {
            ob_end_clean();
        }

        return $res;
    }

    /** @return array<string,mixed> */
    private function doConfig(int $userId, \WP_REST_Request $r): array
    {
        $reasons = [];
        $form = $this->chbs->form($this->settings->bookingFormId());
        if ($form === null) {
            $reasons[] = 'booking_form_missing';
        } else {
            if (!$this->chbs->cashCompatible($form)) {
                $reasons[] = 'payment_not_compatible';
            }
            if ($this->chbs->vehicle($form, $this->settings->vehicleId()) === null) {
                $reasons[] = 'vehicle_unresolved';
            }
            if (count((array) ($form['meta']['location_fixed_pickup_service_type_1'] ?? [])) > 0) {
                $reasons[] = 'fixed_locations';
            }
        }

        return ['data' => [
            'service' => 'distance',
            'payment_methods' => ['cash'],
            'max_passengers' => $this->settings->maxPassengers(),
            'ready' => $reasons === [],
            'blocking_reasons' => $reasons,
            'scheduled_trips' => false,
        ]];
    }

    /** @return array<string,mixed> */
    private function doQuote(int $userId, \WP_REST_Request $r): array
    {
        $this->rateLimit($userId, 'q', 20, 600);

        return ['data' => $this->quotes->quote($userId, $this->body($r))];
    }

    /** @return array<string,mixed> */
    private function doBook(int $userId, \WP_REST_Request $r): array
    {
        $this->rateLimit($userId, 'b', 10, 600);
        $body = $this->body($r);
        if (!isset($body['idempotency_key'])) {
            $h = $r->get_header('Idempotency-Key');
            if (is_string($h) && $h !== '') {
                $body['idempotency_key'] = $h;
            }
        }
        $res = $this->bookings->create($userId, $body);

        return ['data' => ['trip' => $res['trip'], 'replayed' => $res['replayed']], '_status' => $res['replayed'] ? 200 : 201, '_message' => 'Solicitud creada'];
    }

    private function places(): PlacesService
    {
        if ($this->places === null) {
            throw new RiderException('PLACES_UNAVAILABLE');
        }

        return $this->places;
    }

    /** @return array<string,mixed> */
    private function doPlacesSearch(int $userId, \WP_REST_Request $r): array
    {
        $this->rateLimit($userId, 'ps', 120, 600);
        $lat = $r->get_param('lat');
        $lng = $r->get_param('lng');

        return ['data' => ['predictions' => $this->places()->autocomplete(
            (string) $r->get_param('q'),
            is_numeric($lat) ? (float) $lat : null,
            is_numeric($lng) ? (float) $lng : null,
            (string) $r->get_param('session')
        )]];
    }

    /** @return array<string,mixed> */
    private function doPlacesDetails(int $userId, \WP_REST_Request $r): array
    {
        $this->rateLimit($userId, 'pd', 120, 600);

        return ['data' => ['place' => $this->places()->details((string) $r->get_param('place_id'), (string) $r->get_param('session'))]];
    }

    /** @return array<string,mixed> */
    private function doPlacesReverse(int $userId, \WP_REST_Request $r): array
    {
        $this->rateLimit($userId, 'pr', 60, 600);

        return ['data' => ['place' => $this->places()->reverse((float) $r->get_param('lat'), (float) $r->get_param('lng'))]];
    }

    /** @return array<string,mixed> */
    private function doActive(int $userId, \WP_REST_Request $r): array
    {
        $trip = $this->reader->findActiveFor($userId, true);

        return ['data' => ['trip' => $trip]];
    }

    /** @return array<string,mixed> */
    private function doTrip(int $userId, \WP_REST_Request $r): array
    {
        return ['data' => ['trip' => $this->owned($userId, $r)]];
    }

    /** @return array<string,mixed> */
    private function doDriver(int $userId, \WP_REST_Request $r): array
    {
        $trip = $this->owned($userId, $r);

        return ['data' => ['driver' => $trip['driver'], 'driver_location' => $trip['driver_location'], 'status' => $trip['status']]];
    }

    /** @return array<string,mixed> */
    private function doChatToken(int $userId, \WP_REST_Request $r): array
    {
        $trip = $this->owned($userId, $r, false);
        if ($trip['is_terminal'] && $trip['status'] === 'cancelled') {
            throw new RiderException('TRIP_NOT_FOUND');
        }
        $token = function_exists('goride_get_or_create_token') ? (string) goride_get_or_create_token((int) $trip['booking_id'], 'client') : '';
        if ($token === '') {
            throw new RiderException('CHAT_TOKEN_UNAVAILABLE');
        }

        return ['data' => [
            'booking_id' => (int) $trip['booking_id'],
            'token' => $token,
            'chat_base_url' => esc_url_raw(rest_url('goride/v1')),
        ]];
    }

    /** @return array<string,mixed> */
    private function doCancel(int $userId, \WP_REST_Request $r): array
    {
        $res = $this->cancels->cancel($userId, (int) $r['id']);

        return ['data' => ['trip' => $res['trip'], 'already_cancelled' => $res['already_cancelled']], '_message' => 'Viaje cancelado'];
    }

    /** @return array<string,mixed> */
    private function owned(int $userId, \WP_REST_Request $r, bool $withLocation = true): array
    {
        $id = (int) $r['id'];
        if (!$this->reader->isOwner($id, $userId)) {
            throw new RiderException('TRIP_NOT_FOUND');
        }

        return $this->reader->toArray($id, $userId, $withLocation);
    }

    /** @return array<string,mixed> */
    private function body(\WP_REST_Request $r): array
    {
        $b = $r->get_json_params();

        return is_array($b) ? $b : [];
    }

    private function rateLimit(int $userId, string $bucket, int $max, int $window): void
    {
        $key = 'goride_rider_rl_' . $bucket . '_' . $userId;
        $n = (int) get_transient($key);
        if ($n >= $max) {
            throw new RiderException('RATE_LIMITED');
        }
        set_transient($key, $n + 1, $window);
    }

    /** @param array<string,mixed>|null $data */
    private function ok(mixed $data, int $status, string $message): \WP_REST_Response
    {
        return $this->respond(['success' => true, 'code' => null, 'message' => $message, 'data' => $data], $status);
    }

    private function fail(RiderException $e): \WP_REST_Response
    {
        return $this->respond([
            'success' => false, 'code' => $e->errorCode(), 'message' => $e->getMessage(),
            'data' => $e->extra() === [] ? null : $e->extra(),
        ], $e->httpStatus());
    }

    /** @param array<string,mixed> $body */
    private function respond(array $body, int $status): \WP_REST_Response
    {
        $res = new \WP_REST_Response($body, $status);
        $res->header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
        $res->header('Pragma', 'no-cache');

        return $res;
    }
}
