<?php
// Dobles mínimos de WordPress para pruebas AISLADAS (sin base de datos real, sin red, sin producción).
declare(strict_types=1);

$GLOBALS['__posts'] = [];      // id => object
$GLOBALS['__meta'] = [];       // id => [key => value]
$GLOBALS['__options'] = [];
$GLOBALS['__transients'] = [];
$GLOBALS['__routes'] = [];
$GLOBALS['__users'] = [];      // id => ['meta'=>[], 'email'=>, 'display'=>]
$GLOBALS['__current_user'] = 0;
$GLOBALS['__locations'] = [];  // "booking:driver" => row
$GLOBALS['__next_id'] = 1000;
$GLOBALS['__rest_calls'] = [];
$GLOBALS['__cancel_ok'] = true;

class WP_REST_Response
{
    public array $headers = [];
    public function __construct(public $data = null, public int $status = 200) {}
    public function header(string $k, string $v): void { $this->headers[$k] = $v; }
    public function get_data() { return $this->data; }
    public function is_error(): bool { return $this->status >= 400; }
}
class WP_REST_Request implements ArrayAccess
{
    public array $params = [];
    public array $headers = [];
    public function __construct(public string $method = 'GET', public string $route = '') {}
    public function set_body_params(array $p): void { $this->params = array_merge($this->params, $p); }
    public function get_json_params() { return $this->params; }
    public function get_header(string $h) { return $this->headers[strtolower($h)] ?? null; }
    public function get_param(string $k) { return $this->params[$k] ?? null; }
    public function offsetExists(mixed $o): bool { return isset($this->params[$o]); }
    public function offsetGet(mixed $o): mixed { return $this->params[$o] ?? null; }
    public function offsetSet(mixed $o, mixed $v): void { $this->params[$o] = $v; }
    public function offsetUnset(mixed $o): void { unset($this->params[$o]); }
}
class FakeWpdb
{
    public string $prefix = 'wp_';
    public function prepare(string $q, ...$args): string { return vsprintf(str_replace(['%d', '%s', '%f'], ['%s', "'%s'", '%s'], $q), $args); }
    public function get_row(string $q, $out = null)
    {
        foreach ($GLOBALS['__locations'] as $k => $row) {
            [$b, $d] = explode(':', $k);
            if (preg_match("/booking_id='?$b'? AND driver_id='?$d'?/", $q)) { return $row; }
        }
        return null;
    }
}
$GLOBALS['wpdb'] = new FakeWpdb();
const ARRAY_A = 'ARRAY_A';

function add_action(...$a): void {}
function register_rest_route(string $ns, string $route, array $args): void { $GLOBALS['__routes'][] = [$ns, $route, $args]; }
function get_post($id) { return $GLOBALS['__posts'][(int) $id] ?? null; }
function get_post_meta($id, $key = '', $single = false) { return $GLOBALS['__meta'][(int) $id][$key] ?? ''; }
function update_post_meta($id, $key, $v) { $GLOBALS['__meta'][(int) $id][$key] = $v; return true; }
function delete_post_meta($id, $key) { unset($GLOBALS['__meta'][(int) $id][$key]); return true; }
function wp_test_make_booking(array $meta = [], ?int $ts = null): int
{
    $id = $GLOBALS['__next_id']++;
    $GLOBALS['__posts'][$id] = (object) ['ID' => $id, 'post_type' => 'chbs_booking', 'post_date_gmt' => gmdate('Y-m-d H:i:s', $ts ?? time())];
    $GLOBALS['__meta'][$id] = $meta;
    return $id;
}
function get_posts(array $args): array
{
    $out = [];
    foreach ($GLOBALS['__posts'] as $id => $p) {
        if ($p->post_type !== ($args['post_type'] ?? $p->post_type)) { continue; }
        $ok = true;
        foreach ((array) ($args['meta_query'] ?? []) as $k => $q) {
            if (!is_array($q) || !isset($q['key'])) { continue; }
            if ((string) get_post_meta($id, $q['key']) !== (string) $q['value']) { $ok = false; }
        }
        if ($ok) { $out[] = $id; }
    }
    rsort($out);
    return array_slice($out, 0, (int) ($args['numberposts'] ?? 5));
}
function add_option($n, $v = '', $d = '', $a = 'yes'): bool { if (array_key_exists($n, $GLOBALS['__options'])) { return false; } $GLOBALS['__options'][$n] = $v; return true; }
function get_option($n, $d = false) { return $GLOBALS['__options'][$n] ?? $d; }
function delete_option($n): bool { unset($GLOBALS['__options'][$n]); return true; }
function get_transient($k) { return $GLOBALS['__transients'][$k] ?? false; }
function set_transient($k, $v, $t = 0): bool { $GLOBALS['__transients'][$k] = $v; return true; }
function wp_timezone(): DateTimeZone { return new DateTimeZone('America/New_York'); }
function get_current_user_id(): int { return $GLOBALS['__current_user']; }
function wp_set_current_user($id) { $GLOBALS['__current_user'] = (int) $id; }
function get_userdata($id) { $u = $GLOBALS['__users'][$id] ?? null; return $u ? (object) ['user_email' => $u['email'], 'display_name' => $u['display']] : false; }
function get_user_meta($id, $k, $s = false) { return $GLOBALS['__users'][$id]['meta'][$k] ?? ''; }
function rest_url($p = '') { return 'https://goride.website/wp-json/' . ltrim($p, '/'); }
function esc_url_raw($u) { return $u; }
function wp_strip_all_tags($s) { return strip_tags((string) $s); }
function wp_get_attachment_url($id) { return $id > 0 ? 'https://goride.website/wp-content/uploads/driver-' . $id . '.jpg' : false; }
function goride_get_or_create_token($id, $who) { $k = $who === 'driver' ? '_goride_driver_token' : '_goride_client_token'; if (!get_post_meta($id, $k)) { update_post_meta($id, $k, 'tok_' . $who . '_' . $id); } return get_post_meta($id, $k); }
function rest_do_request($req)
{
    $GLOBALS['__rest_calls'][] = [$req->route, $req->params];
    if ($GLOBALS['__cancel_ok']) {
        update_post_meta((int) $req->params['booking_id'], '_goride_live_status', 'cancelled_by_user');
        return new WP_REST_Response(['ok' => true], 200);
    }
    return new WP_REST_Response(['ok' => false, 'error' => 'bad_token'], 403);
}
