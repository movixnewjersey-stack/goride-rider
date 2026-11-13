<?php
/**
 * Pruebas aisladas de goride-rider-api. NO tocan WordPress, base de datos,
 * red ni producción. Uso:  php tests/run_tests.php
 */
declare(strict_types=1);

define('ABSPATH', __DIR__);
require __DIR__ . '/wp_stubs.php';
foreach ([
    'Support/RiderException', 'Support/Geo', 'Support/QuoteToken', 'Support/TripState',
    'Services/ChbsGateway', 'Services/ChbsGatewayLive', 'Services/Settings', 'Services/ZoneGuard',
    'Services/ChbsDataBuilder', 'Services/TripReader', 'Services/QuoteService', 'Services/BookingService',
    'Services/CancelService', 'Services/PlacesService', 'Services/RiderAuth', 'Rest/RiderController',
] as $f) {
    require __DIR__ . '/../goride-rider-api/src/' . $f . '.php';
}
require __DIR__ . '/fake_gateway.php';

use GoRideRider\Rest\RiderController;
use GoRideRider\Services\{BookingService, CancelService, QuoteService, RiderAuth, Settings, TripReader, ZoneGuard};
use GoRideRider\Support\{Geo, QuoteToken, RiderException, TripState};

$pass = 0; $fail = 0;
function ok(bool $c, string $name): void { global $pass, $fail; if ($c) { $pass++; echo "  ok   $name\n"; } else { $fail++; echo "  FAIL $name\n"; } }
function throwsCode(callable $fn, string $code, string $name): void
{
    try { $fn(); ok(false, "$name (no lanzó)"); } catch (RiderException $e) { ok($e->errorCode() === $code, "$name [{$e->errorCode()}]"); }
}
function reset_world(): void { foreach (['__posts', '__meta', '__options', '__transients', '__locations', '__rest_calls'] as $k) { $GLOBALS[$k] = []; } $GLOBALS['__cancel_ok'] = true; $GLOBALS['__current_user'] = 0; }
function mk(?FakeGateway $g = null): array
{
    $g ??= new FakeGateway();
    $s = new Settings();
    $t = new QuoteToken('test-secret', 600);
    $z = new ZoneGuard($g);
    $r = new TripReader(static fn(int $id): ?float => $g->bookingTotal($id));
    $contact = static fn(int $u): array => $GLOBALS['__users'][$u]['contact'] ?? ['first_name' => 'Ana', 'last_name' => 'Pérez', 'email' => 'ana@example.com', 'phone' => '+19735550100'];
    $q = new QuoteService($g, $s, $t, $z);
    $b = new BookingService($g, $s, $t, $z, $r, $contact);
    $c = new CancelService($r, static fn(int $id, string $tok): bool => (rest_do_request((function () use ($id, $tok) { $x = new WP_REST_Request('POST', '/goride/v1/cancel'); $x->set_body_params(['booking_id' => $id, 'token' => $tok]); return $x; })()))->get_data()['ok'] ?? false);
    return compact('g', 's', 't', 'z', 'r', 'q', 'b', 'c');
}
$in = fn(array $o = []) => array_merge(['pickup' => ['lat' => 40.7357, 'lng' => -74.1724, 'address' => 'Newark, NJ', 'country_code' => 'US'], 'dropoff' => ['lat' => 40.7128, 'lng' => -74.0060, 'address' => 'New York, NY'], 'passengers' => 2], $o);

echo "== TripState\n";
$n = 1_000_000;
ok(TripState::resolve('', 'running', $n - 60, $n) === 'searching', 'running => searching');
ok(TripState::resolve('', 'no_drivers', $n - 60, $n) === 'no_drivers', 'no_drivers');
ok(TripState::resolve('', 'dispatch_failed', $n - 60, $n) === 'no_drivers', 'dispatch_failed => no_drivers');
ok(TripState::resolve('', 'no_drivers_in_radius', $n - 60, $n) === 'searching', 'no_drivers_in_radius es transitorio => searching');
ok(TripState::resolve('', 'running', $n - 2000, $n) === 'no_drivers', 'búsqueda vencida (30 min) => no_drivers (solo lectura)');
ok(TripState::resolve('accepted', 'accepted', $n - 2000, $n) === 'driver_assigned', 'accepted gana sobre antigüedad');
ok(TripState::resolve('arrived_at_pickup', 'accepted', $n, $n) === 'driver_arrived', 'arrived');
ok(TripState::resolve('finished', '', $n, $n) === 'finished', 'finished');
ok(TripState::resolve('cancelled_by_user', '', $n, $n) === 'cancelled', 'cancelled');
ok(TripState::resolve('accepted', 'cancelled_by_user', $n, $n) === 'cancelled', 'offer cancelada prevalece');
ok(TripState::isCancelable('driver_assigned') && !TripState::isCancelable('finished') && !TripState::isCancelable('cancelled'), 'cancelables');
ok(!TripState::blocksNewRequest('no_drivers') && TripState::blocksNewRequest('searching'), 'no_drivers no bloquea nuevo pedido');

echo "== QuoteToken\n";
$tk = new QuoteToken('s', 600); $tok = $tk->issue(['uid' => 5, 'gross' => 10.0], 1000);
ok($tk->verify($tok, 5, 1100)['gross'] == 10.0, 'verifica');
throwsCode(fn() => $tk->verify($tok, 6, 1100), 'QUOTE_INVALID', 'otro usuario');
throwsCode(fn() => $tk->verify($tok, 5, 1700), 'QUOTE_EXPIRED', 'vencido');
[$b64, $sig] = explode('.', $tok);
$evil = rtrim(strtr(base64_encode(json_encode(['uid' => 5, 'gross' => 0.01, 'exp' => 99999999])), '+/', '-_'), '=');
throwsCode(fn() => $tk->verify($evil . '.' . $sig, 5, 1100), 'QUOTE_INVALID', 'payload alterado (precio)');
throwsCode(fn() => (new QuoteToken('otra', 600))->verify($tok, 5, 1100), 'QUOTE_INVALID', 'otra llave');
throwsCode(fn() => $tk->verify('basura', 5, 1100), 'QUOTE_INVALID', 'malformado');

echo "== Geo\n";
ok(Geo::validLat(40.7) && !Geo::validLat(91) && !Geo::validLng(181) && !Geo::validLat('abc') && !Geo::validLat(NAN), 'rangos');
throwsCode(fn() => Geo::normalizePoint(['lat' => 'x', 'lng' => 1], 'pickup'), 'VALIDATION_ERROR', 'punto inválido');
$np = Geo::normalizePoint(['lat' => 1, 'lng' => 2, 'address' => "Calle \"1\"\n", 'country_code' => 'usa'], 'p');
ok($np['address'] === 'Calle 1' && $np['country_code'] === 'US', 'sanea dirección y país');
ok(abs(Geo::distanceKm(40.7357, -74.1724, 40.7128, -74.0060) - 14.4) < 1.0, 'haversine Newark-NYC ~14 km');

echo "== ZoneGuard\n";
reset_world(); $m = mk(); $pu = ['lat' => 40.7, 'lng' => -74.1, 'country_code' => 'US'];
$m['z']->assertAllowed($m['g']->form, $pu, $pu); ok(true, 'US permitido');
$m['g']->country = 'CO'; throwsCode(fn() => $m['z']->assertAllowed($m['g']->form, $pu, $pu), 'ZONE_NOT_ALLOWED', 'país no permitido (geocodificado en servidor)');
$m['g']->country = null; throwsCode(fn() => $m['z']->assertAllowed($m['g']->form, $pu, $pu), 'ZONE_UNVERIFIABLE', 'país no verificable => falla cerrado');
$m['g']->country = 'CO'; $pu2 = $pu; $pu2['country_code'] = 'US'; // el cliente miente
throwsCode(fn() => $m['z']->assertAllowed($m['g']->form, $pu2, $pu2), 'ZONE_NOT_ALLOWED', 'el país declarado por el cliente se ignora');
$m['g']->country = 'US'; $m['g']->zone['pickup'] = ['enabled' => true, 'countries' => [], 'area' => 'Newark', 'area_lat' => 40.7357, 'area_lng' => -74.1724, 'radius_km' => 20.0];
$m['z']->assertAllowed($m['g']->form, $pu, $pu); ok(true, 'dentro del radio');
throwsCode(fn() => $m['z']->assertAllowed($m['g']->form, ['lat' => 34.0, 'lng' => -118.2, 'country_code' => 'US'], $pu), 'ZONE_NOT_ALLOWED', 'fuera del radio');
$m['g']->zone['relation'] = 2; $m['z']->assertAllowed($m['g']->form, ['lat' => 34.0, 'lng' => -118.2, 'country_code' => 'US'], $pu); ok(true, 'relación OR');
$m['g']->zone['pickup']['enabled'] = false; $m['g']->zone['relation'] = 1;
$m['z']->assertAllowed($m['g']->form, ['lat' => 34.0, 'lng' => -118.2, 'country_code' => 'US'], $pu); ok(true, 'restricción desactivada = permitido');

echo "== QuoteService\n";
reset_world(); $m = mk(); $q = $m['q'];
$r = $q->quote(5, $in(), 1000);
ok($r['price']['total'] === 18.45 && $r['payment_method'] === 'cash' && $r['distance_km'] === 12.3 && $r['duration_min'] === 25, 'cotiza con precio del servidor');
ok(count($GLOBALS['__posts']) === 0 && $m['g']->createCalls === 0, 'cotizar NO crea reserva');
$r2 = $q->quote(5, $in(['price' => 0.01, 'distance_km' => 0.1, 'total' => 1]), 1000);
ok($r2['price']['total'] === 18.45 && $r2['distance_km'] === 12.3, 'precio/distancia enviados por el cliente se ignoran');
throwsCode(fn() => $q->quote(5, $in(['dropoff' => ['lat' => 40.7357, 'lng' => -74.1724]])), 'SAME_LOCATION', 'mismo punto');
throwsCode(fn() => $q->quote(5, $in(['pickup_at' => '2026-12-01T10:00:00Z'])), 'VALIDATION_ERROR', 'programado no soportado en MVP');
throwsCode(fn() => $q->quote(5, $in(['passengers' => 0])), 'VALIDATION_ERROR', 'pasajeros 0');
throwsCode(fn() => $q->quote(5, $in(['passengers' => 99])), 'VALIDATION_ERROR', 'pasajeros > máximo');
throwsCode(fn() => $q->quote(5, $in(['passengers' => 1.5])), 'VALIDATION_ERROR', 'pasajeros decimal');
throwsCode(fn() => $q->quote(5, ['pickup' => null, 'dropoff' => null]), 'VALIDATION_ERROR', 'sin puntos');
throwsCode(fn() => $q->quote(5, $in(['dropoff' => ['lat' => 10, 'lng' => 10]])), 'VALIDATION_ERROR', 'destino absurdamente lejos');
$m['g']->cash = false; throwsCode(fn() => $q->quote(5, $in()), 'PAYMENT_NOT_COMPATIBLE', 'efectivo incompatible: se informa, no se cambia config'); $m['g']->cash = true;
$m['g']->vehicle = null; throwsCode(fn() => $q->quote(5, $in()), 'QUOTE_UNAVAILABLE', 'vehículo no resoluble'); $m['g']->vehicle = ['id' => 77, 'name' => 'Automóvil'];
$m['g']->gross = 0.0; throwsCode(fn() => $q->quote(5, $in()), 'QUOTE_UNAVAILABLE', 'precio 0 rechazado'); $m['g']->gross = 18.45;
$m['g']->form['meta']['location_fixed_pickup_service_type_1'] = [1 => 'x']; throwsCode(fn() => $q->quote(5, $in()), 'QUOTE_UNAVAILABLE', 'formulario con ubicaciones fijas no soportado'); $m['g']->form['meta']['location_fixed_pickup_service_type_1'] = [];
$m['g']->country = 'CO'; throwsCode(fn() => $q->quote(5, $in()), 'ZONE_NOT_ALLOWED', 'zona fuera'); $m['g']->country = 'US';

echo "== BookingService\n";
reset_world(); $GLOBALS['__users'][5] = ['email' => 'ana@example.com']; $m = mk(); $g = $m['g'];
$quote = $m['q']->quote(5, $in(), time());
$res = $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0001']);
$bid = $res['trip']['booking_id'];
ok(!$res['replayed'] && $g->createCalls === 1 && $res['trip']['status'] === 'searching', 'crea la reserva');
ok((int) get_post_meta($bid, '_goride_user_id') === 5, 'reserva vinculada al usuario (_goride_user_id)');
ok(get_post_meta($bid, '_goride_rider_created_via') === 'rider_app', 'marcada como rider_app');
ok($g->lastCreateData['payment_id'] === 1 && $g->lastCreateData['client_contact_detail_phone_number'] === '+19735550100', 'efectivo + contacto del perfil (no del cliente)');
ok($g->lastCreateData['pickup_date_service_type_1'] === (new DateTimeImmutable('now', wp_timezone()))->format('d-m-Y'), 'fecha en formato estándar CHBS d-m-Y');
ok($res['trip']['price_matches_quote'] === true, 'precio guardado coincide con la cotización');
ok(!array_key_exists('token', $res['trip']) && !str_contains(json_encode($res['trip']), 'tok_'), 'la respuesta no contiene tokens');
$again = $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0001']);
ok($again['replayed'] && $again['trip']['booking_id'] === $bid && $g->createCalls === 1, 'doble toque / reintento: misma reserva, 1 sola creación');
ok($GLOBALS['__options'] === [], 'candados liberados tras éxito');
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'otra-clave-0002']), 'ACTIVE_TRIP_EXISTS', 'segundo pedido con viaje activo');
ok($g->createCalls === 1, 'no se creó segunda reserva');

reset_world(); $m = mk(); $g = $m['g']; $quote = $m['q']->quote(5, $in(), time());
add_option('goride_rider_uk_5', (string) time()); // solicitud simultánea en curso
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0003']), 'REQUEST_IN_PROGRESS', 'solicitud simultánea');
ok($g->createCalls === 0, 'simultánea no crea reserva'); delete_option('goride_rider_uk_5');
add_option('goride_rider_uk_5', (string) (time() - 500)); // candado huérfano viejo
$ok = $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0003']); ok(!$ok['replayed'], 'candado huérfano antiguo se libera solo');

reset_world(); $m = mk(); $g = $m['g']; $quote = $m['q']->quote(5, $in(), time());
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id']]), 'IDEMPOTENCY_REQUIRED', 'sin clave de idempotencia');
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'x']), 'VALIDATION_ERROR', 'clave inválida');
throwsCode(fn() => $m['b']->create(6, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0004']), 'QUOTE_INVALID', 'cotización de otro usuario');
throwsCode(fn() => $m['b']->create(5, ['quote_id' => 'abc.def', 'idempotency_key' => 'abcdefgh-0004']), 'QUOTE_INVALID', 'cotización falsa');
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0004'], time() + 700), 'QUOTE_EXPIRED', 'cotización vencida');
$g->gross = 21.00; $e = null;
try { $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0005']); } catch (RiderException $x) { $e = $x; }
ok($e && $e->errorCode() === 'PRICE_CHANGED' && $e->extra()['price']['total'] === 21.0 && $g->createCalls === 0, 'tarifa cambió: PRICE_CHANGED con nuevo precio y sin crear'); $g->gross = 18.45;
$g->cash = false; throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0006']), 'PAYMENT_NOT_COMPATIBLE', 'pago ya no compatible'); $g->cash = true;
$g->country = 'CO'; throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0007']), 'ZONE_NOT_ALLOWED', 'zona cambió'); $g->country = 'US';
$GLOBALS['__users'][5]['contact'] = ['first_name' => 'Ana', 'last_name' => 'P', 'email' => 'a@a.com', 'phone' => ''];
throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0008']), 'VALIDATION_ERROR', 'sin teléfono en el perfil'); unset($GLOBALS['__users'][5]['contact']);
$g->createFails = true; throwsCode(fn() => $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0009']), 'BOOKING_CREATION_FAILED', 'CHBS falla: no se simula éxito');
ok($GLOBALS['__options'] === [] && count($GLOBALS['__posts']) === 0, 'tras fallo: candados liberados y sin reservas'); $g->createFails = false;
$retry = $m['b']->create(5, ['quote_id' => $quote['quote_id'], 'idempotency_key' => 'abcdefgh-0009']); ok(!$retry['replayed'] && count($GLOBALS['__posts']) === 1, 'reintento tras fallo crea una reserva');
// misma clave, otro usuario: no devuelve la reserva ajena
$GLOBALS['__users'][6] = []; $q6 = $m['q']->quote(6, $in(), time());
$o = $m['b']->create(6, ['quote_id' => $q6['quote_id'], 'idempotency_key' => 'abcdefgh-0009']);
ok(!$o['replayed'] && $o['trip']['booking_id'] !== $retry['trip']['booking_id'], 'la clave de idempotencia está aislada por usuario');

echo "== TripReader\n";
reset_world(); $m = mk(); $r = $m['r'];
$legacy = wp_test_make_booking(['chbs_client_contact_detail_email_address' => 'ana@example.com']);
ok(!$r->isOwner($legacy, 5), 'reserva sin _goride_user_id NO es de nadie (no se confía en email)');
$GLOBALS['__posts'][9001] = (object) ['ID' => 9001, 'post_type' => 'chbs_driver']; $GLOBALS['__meta'][9001] = ['chbs_first_name' => 'Carlos', 'chbs_contact_phone_number' => '555', 'chbs_contact_email_address' => 'c@x.com', '_thumbnail_id' => 12];
$trip = wp_test_make_booking(['_goride_user_id' => 5, '_goride_live_status' => 'accepted', '_goride_offer_state' => 'accepted', '_goride_assigned_driver_id' => 9001, 'chbs_driver_id' => 9001, 'chbs_vehicle_name' => 'Automóvil', 'chbs_coordinate' => [['lat' => 1.0, 'lng' => 2.0, 'address' => 'A'], ['lat' => 3.0, 'lng' => 4.0, 'address' => 'B']]]);
ok($r->isOwner($trip, 5) && !$r->isOwner($trip, 6) && !$r->isOwner(424242, 5) && !$r->isOwner($trip, 0), 'propiedad estricta');
$GLOBALS['__locations']["$trip:9001"] = ['lat' => '40.1', 'lng' => '-74.2', 'accuracy' => '8', 'updated_at' => (new DateTimeImmutable('-20 seconds', wp_timezone()))->format('Y-m-d H:i:s')];
$a = $r->toArray($trip, 5);
ok($a['status'] === 'driver_assigned' && $a['driver']['first_name'] === 'Carlos' && $a['driver']['photo_url'] !== null, 'conductor asignado con nombre y foto');
ok(!str_contains(json_encode($a), '555') && !str_contains(json_encode($a), 'c@x.com'), 'privacidad: no expone teléfono ni email del conductor');
ok($a['driver_location']['lat'] === 40.1 && $a['driver_location']['age_seconds'] >= 19 && $a['driver_location']['age_seconds'] <= 40, 'ubicación del conductor con antigüedad');
ok($a['can_cancel'] === true && $a['pickup']['address'] === 'A' && $a['dropoff']['lat'] === 3.0, 'datos de ruta y can_cancel');
$act = $r->findActiveFor(5); ok($act !== null && $act['booking_id'] === $trip, 'recupera viaje activo');
ok($r->findActiveFor(6) === null, 'otro usuario no ve viajes ajenos');
update_post_meta($trip, '_goride_live_status', 'finished'); unset($GLOBALS['__meta'][$trip]['_goride_assigned_driver_id']);
$f = $r->toArray($trip, 5); ok($f['status'] === 'finished' && $f['driver']['first_name'] === 'Carlos' && $f['driver_location'] === null && !$f['can_cancel'], 'finalizado: conserva conductor (chbs_driver_id) y no ofrece ubicación');
ok($r->findActiveFor(5) === null, 'finalizado ya no es viaje activo');
$nd = wp_test_make_booking(['_goride_user_id' => 5, '_goride_offer_state' => 'no_drivers']);
ok($r->findActiveFor(5)['status'] === 'no_drivers', 'sin conductores reciente se recupera para mostrar resultado');
$old = wp_test_make_booking(['_goride_user_id' => 9, '_goride_offer_state' => 'no_drivers'], time() - 5000); ok($r->findActiveFor(9) === null, 'sin conductores antiguo no se recupera');

echo "== CancelService\n";
reset_world(); $m = mk(); $c = $m['c'];
$t1 = wp_test_make_booking(['_goride_user_id' => 5, '_goride_offer_state' => 'running']);
throwsCode(fn() => $c->cancel(6, $t1), 'TRIP_NOT_FOUND', 'otro usuario: 404 (no revela existencia)');
throwsCode(fn() => $c->cancel(5, 777777), 'TRIP_NOT_FOUND', 'reserva inexistente');
$x = $c->cancel(5, $t1); ok($x['trip']['status'] === 'cancelled' && !$x['already_cancelled'] && count($GLOBALS['__rest_calls']) === 1, 'cancela vía ruta existente');
ok($GLOBALS['__rest_calls'][0][0] === '/goride/v1/cancel' && $GLOBALS['__rest_calls'][0][1]['token'] === 'tok_client_' . $t1, 'usa token de cliente interno del servidor');
$y = $c->cancel(5, $t1); ok($y['already_cancelled'] && count($GLOBALS['__rest_calls']) === 1, 'doble toque: idempotente, no repite la cancelación');
$t2 = wp_test_make_booking(['_goride_user_id' => 5, '_goride_live_status' => 'finished']);
throwsCode(fn() => $c->cancel(5, $t2), 'TRIP_NOT_CANCELABLE', 'viaje finalizado no se cancela'); ok(count($GLOBALS['__rest_calls']) === 1, 'no invocó la cancelación');
$t3 = wp_test_make_booking(['_goride_user_id' => 5, '_goride_live_status' => 'arrived_at_pickup']);
$c->cancel(5, $t3); ok(get_post_meta($t3, '_goride_live_status') === 'cancelled_by_user', 'cancela con conductor en el punto');
$GLOBALS['__cancel_ok'] = false; $t4 = wp_test_make_booking(['_goride_user_id' => 5]);
throwsCode(fn() => $c->cancel(5, $t4), 'CANCEL_FAILED', 'si la cancelación existente falla se informa'); $GLOBALS['__cancel_ok'] = true;

echo "== RiderController (HTTP)\n";
reset_world(); $GLOBALS['__users'][5] = ['email' => 'ana@example.com', 'display' => 'Ana']; $m = mk(); $g = $m['g'];
$mkc = function (?callable $auth = null) use ($m, $g) {
    $auth ??= static function (WP_REST_Request $r): int { $h = $r->get_header('authorization'); if (!$h) { throw new RuntimeException('AUTH_TOKEN_MISSING'); } return $h === 'Bearer u5' ? 5 : ($h === 'Bearer u6' ? 6 : throw new RuntimeException('AUTH_INVALID_TOKEN')); };
    return new RiderController(new RiderAuth($auth), $m['q'], $m['b'], $m['c'], $m['r'], $g, $m['s']);
};
$ctl = $mkc();
$req = function (string $m_, array $p = [], ?string $tok = 'Bearer u5') { $r = new WP_REST_Request($m_); $r->params = $p; if ($tok) { $r->headers['authorization'] = $tok; } return $r; };
$res = $ctl->run($req('POST', $in(), null), 'quote'); ok($res->status === 401 && $res->data['code'] === 'AUTH_TOKEN_MISSING', 'sin token => 401');
$res = $ctl->run($req('POST', $in(), 'Bearer zzz'), 'quote'); ok($res->status === 401 && $res->data['code'] === 'AUTH_INVALID_TOKEN', 'token inválido => 401');
$res = $ctl->run($req('POST', $in()), 'quote'); ok($res->status === 200 && $res->data['success'] === true && isset($res->data['data']['quote_id']), 'cotización 200 con sobre estándar');
ok(str_contains($res->headers['Cache-Control'], 'no-store'), 'sin caché');
$qid = $res->data['data']['quote_id'];
$g->noisy = true; $res = $ctl->run($req('POST', $in()), 'quote'); $g->noisy = false;
ok($res->status === 200 && is_array($res->data), 'salida PHP impresa por código legado de CHBS no rompe la respuesta');
$res = $ctl->run($req('POST', ['quote_id' => $qid, 'idempotency_key' => 'abcdefgh-1111']), 'book'); ok($res->status === 201 && $res->data['data']['replayed'] === false, 'reserva => 201');
$bid = $res->data['data']['trip']['booking_id'];
$res = $ctl->run($req('POST', ['quote_id' => $qid, 'idempotency_key' => 'abcdefgh-1111']), 'book'); ok($res->status === 200 && $res->data['data']['replayed'] === true, 'reintento => 200 replayed');
$r2_ = $req('POST', ['quote_id' => $qid]); $r2_->headers['idempotency-key'] = 'abcdefgh-1111'; $res = $ctl->run($r2_, 'book'); ok($res->status === 200 && $res->data['data']['replayed'] === true, 'acepta cabecera Idempotency-Key');
$rq = $req('GET'); $rq->params['id'] = (string) $bid; $res = $ctl->run($rq, 'trip'); ok($res->status === 200 && $res->data['data']['trip']['booking_id'] === $bid, 'GET trip del dueño');
$rq6 = $req('GET', [], 'Bearer u6'); $rq6->params['id'] = (string) $bid; $res = $ctl->run($rq6, 'trip'); ok($res->status === 404 && $res->data['code'] === 'TRIP_NOT_FOUND', 'GET trip de otro => 404');
$res = $ctl->run($rq6, 'chatToken'); ok($res->status === 404 && !str_contains(json_encode($res->data), 'tok_'), 'chat-token a no dueño: 404 sin token');
$res = $ctl->run($rq, 'chatToken'); ok($res->status === 200 && $res->data['data']['token'] === 'tok_client_' . $bid && $res->data['data']['booking_id'] === $bid, 'chat-token al dueño');
$res = $ctl->run($req('GET'), 'active'); ok($res->status === 200 && $res->data['data']['trip']['booking_id'] === $bid, 'active recupera');
$res = $ctl->run($req('GET', [], 'Bearer u6'), 'active'); ok($res->data['data']['trip'] === null, 'active de otro usuario: null');
$res = $ctl->run($rq, 'driver'); ok($res->status === 200 && $res->data['data']['driver'] === null && $res->data['data']['status'] === 'searching', 'driver: null mientras se busca');
$res = $ctl->run($rq, 'cancel'); ok($res->status === 200 && $res->data['data']['trip']['status'] === 'cancelled', 'cancelar');
$res = $ctl->run($rq, 'cancel'); ok($res->status === 200 && $res->data['data']['already_cancelled'] === true, 'cancelar de nuevo: idempotente');
$res = $ctl->run($req('GET'), 'config'); ok($res->data['data']['ready'] === true && $res->data['data']['payment_methods'] === ['cash'], 'config lista');
$g->cash = false; $res = $ctl->run($req('GET'), 'config'); ok($res->data['data']['ready'] === false && in_array('payment_not_compatible', $res->data['data']['blocking_reasons'], true), 'config informa pago incompatible'); $g->cash = true;
// excepción inesperada: 500 sin filtrar detalles internos
$boom = new RiderController(new RiderAuth(static fn($r) => 5), $m['q'], $m['b'], $m['c'], $m['r'], new class extends FakeGateway { public function form(int $id): ?array { throw new RuntimeException('SECRET db password=xyz'); } }, $m['s']);
$res = $boom->run($req('GET'), 'config'); ok($res->status === 500 && $res->data['code'] === 'INTERNAL_ERROR' && !str_contains(json_encode($res->data), 'xyz'), 'error interno: 500 sin filtrar detalles');
// límite de frecuencia en cotizaciones
reset_world(); $m = mk(); $ctl = new RiderController(new RiderAuth(static fn($r) => 5), $m['q'], $m['b'], $m['c'], $m['r'], $m['g'], $m['s']);
$last = null; for ($i = 0; $i < 21; $i++) { $last = $ctl->run($req('POST', $in()), 'quote'); }
ok($last->status === 429 && $last->data['code'] === 'RATE_LIMITED', 'límite de 20 cotizaciones / 10 min');

echo "== PlacesService\n";
reset_world(); $m = mk(); $urls = [];
$resp = ['status' => 'OK', 'predictions' => [['place_id' => 'ChIJabcdefghij', 'description' => 'x', 'structured_formatting' => ['main_text' => 'Newark Penn', 'secondary_text' => 'Newark, NJ']], ['description' => 'sin id']]];
$ps = new \GoRideRider\Services\PlacesService(function (string $u) use (&$urls, &$resp) { $urls[] = $u; return $resp; }, static fn() => 'KEY123', $m['g'], $m['s']);
$out = $ps->autocomplete('Newark', 40.7, -74.1, 'sess1234abcd');
ok(count($out) === 1 && $out[0]['primary'] === 'Newark Penn', 'autocomplete filtra sin place_id');
ok(str_contains($urls[0], 'key=KEY123') && str_contains($urls[0], 'language=es'), 'llave solo en la URL del servidor');
throwsCode(fn() => $ps->autocomplete('ab', null, null, ''), 'VALIDATION_ERROR', 'consulta demasiado corta');
$resp = ['status' => 'OVER_QUERY_LIMIT'];
throwsCode(fn() => $ps->autocomplete('Newark', null, null, ''), 'PLACES_UNAVAILABLE', 'estado de Google inválido => 503');
$resp = ['status' => 'OK', 'result' => ['geometry' => ['location' => ['lat' => 40.73, 'lng' => -74.17]], 'formatted_address' => 'Newark, NJ 07102, USA', 'address_components' => [['types' => ['postal_code'], 'long_name' => '07102', 'short_name' => '07102'], ['types' => ['country'], 'long_name' => 'United States', 'short_name' => 'US']]]];
$d = $ps->details('ChIJabcdefghij', 'sess1234abcd');
ok($d['lat'] === 40.73 && $d['zip_code'] === '07102' && $d['country_code'] === 'US', 'details con zip y país');
throwsCode(fn() => $ps->details('bad id!', ''), 'VALIDATION_ERROR', 'place_id inválido');
$noKey = new \GoRideRider\Services\PlacesService(fn($u) => $resp, static fn() => '', $m['g'], $m['s']);
throwsCode(fn() => $noKey->autocomplete('Newark', null, null, ''), 'PLACES_UNAVAILABLE', 'sin llave => 503');
$resp = ['status' => 'OK', 'results' => [['place_id' => 'ChIJrev1234567', 'formatted_address' => 'Calle 1', 'address_components' => []]]];
$rv = $ps->reverse(40.1, -74.2); ok($rv['lat'] === 40.1 && $rv['address'] === 'Calle 1', 'reverse conserva coordenadas pedidas');
throwsCode(fn() => $ps->reverse(99.0, 0.0), 'VALIDATION_ERROR', 'reverse con lat inválida');

echo "== Registro de rutas y aislamiento\n";
$GLOBALS['__routes'] = [];
$ctl->register();
$paths = array_map(fn($r) => $r[0] . $r[1], $GLOBALS['__routes']);
ok(count($paths) === 11, '11 rutas registradas');
ok(count(array_unique(array_map(fn($r) => $r[0], $GLOBALS['__routes']))) === 1 && $GLOBALS['__routes'][0][0] === 'goride-rider/v1', 'solo namespace goride-rider/v1 (no toca goride/v1 ni goride/v2)');
$src = '';
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator(__DIR__ . '/../goride-rider-api')) as $f) { if ($f->isFile() && str_ends_with((string) $f, '.php')) { $src .= file_get_contents((string) $f); } }
ok(!preg_match("/update_post_meta\([^)]*_goride_(live_status|assigned_driver_id|offer_state|driver_token)/", $src), 'el plugin nunca escribe estado de viaje, asignación ni token de conductor');
ok(!preg_match('/register_rest_route\([^;]*[\'"]goride\/v[12][\'"]/', $src), 'no registra rutas en namespaces existentes');
ok(!str_contains($src, 'goride_dispatch') && !str_contains($src, 'FCMService') && !str_contains($src, 'goride_notify_client_status'), 'no toca despacho ni FCM de conductores');
ok(!preg_match('/dbDelta|CREATE TABLE|\$wpdb->(insert|update|delete|query)/', $src), 'no crea tablas ni escribe con $wpdb');
ok(!str_contains($src, 'wp_create_nonce') && !preg_match('/get_param\([\'"]token[\'"]\)/', $src), 'no acepta token de reserva del cliente como credencial');

echo "\n== Moneda de CHBS en llamadas REST (ChbsGatewayLive) ==\n";
// Réplica fiel de CHBSCurrency::getFormCurrency()/getExchangeRate() del CHBS real (leídas del plugin del usuario).
if (!class_exists('CHBSCurrency')) {
    class CHBSCurrency
    {
        public static function getBaseCurrency() { return 'USD'; }
        public static function getFormCurrency() { return array_key_exists('currency', $_GET) ? $_GET['currency'] : null; }
        public static function getExchangeRate() { return self::getBaseCurrency() != self::getFormCurrency() ? 0 : 1; }
    }
    class CHBSPrice { public static function format($v, $c) { return '$' . number_format((float) $v, 2); } }
    class CHBSBooking
    {
        public function calculatePrice($data, $a, $b, $c)
        {
            $g = 30.14 * CHBSCurrency::getExchangeRate();
            return ['total' => ['sum' => ['gross' => ['value' => $g, 'format' => (string) $g], 'net' => ['value' => $g, 'format' => (string) $g]]]];
        }
        public function sendBooking($data, $form) { return CHBSCurrency::getExchangeRate() > 0 ? 555 : false; }
        public function createBilling($id) { return ['summary' => ['value_gross' => 30.14 * CHBSCurrency::getExchangeRate()]]; }
    }
}
unset($_GET['currency']);
ok((new CHBSBooking())->calculatePrice([], null, false, true)['total']['sum']['gross']['value'] == 0, 'sin moneda en el contexto CHBS da precio 0 (reproduce el fallo real)');
$live = new GoRideRider\Services\ChbsGatewayLive();
$p = $live->price(['meta' => []], []);
ok($p['gross'] > 30.0 && $p['currency'] === 'USD', 'con el contexto de moneda el precio de CHBS sale correcto [' . $p['gross'] . ' ' . $p['currency'] . ']');
ok(!array_key_exists('currency', $_GET), 'se restaura $_GET (no deja la moneda puesta)');
$_GET['currency'] = 'EUR';
$live->price(['meta' => []], []);
ok($_GET['currency'] === 'EUR', 'si ya había moneda en $_GET se restaura el valor original');
unset($_GET['currency']);
ok($live->create(['meta' => []], [], 1) === 555, 'crear la reserva también usa la moneda base');
ok(abs($live->bookingTotal(5) - 30.14) < 0.001, 'el total de la reserva también usa la moneda base');
ok(!array_key_exists('currency', $_GET), 'tras crear/leer total tampoco queda moneda en $_GET');

echo "\n$pass pruebas correctas, $fail fallidas\n";
exit($fail === 0 ? 0 : 1);
