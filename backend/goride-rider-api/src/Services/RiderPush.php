<?php

declare(strict_types=1);

namespace GoRideRider\Services;

use GoRideRider\Support\RiderException;

/**
 * Avisos push (FCM) al PASAJERO. Reutiliza FCMService de goride-api (sin
 * modificar su comportamiento para el conductor) y NO escribe en ninguna
 * tabla: solo guarda el token FCM del pasajero en user meta propia.
 *
 * Eventos:
 *  - conductor aceptó      (_goride_live_status = accepted)
 *  - conductor llegó       (_goride_live_status = arrived_at_pickup)
 *  - viaje finalizado      (_goride_live_status = finished)
 *  - mensaje del conductor (acción goride_chat_message_inserted, sender = driver)
 *
 * Nunca lanza: un fallo de envío jamás debe romper el flujo del viaje.
 */
final class RiderPush
{
    public const META_TOKEN = 'goride_rider_fcm_token';
    public const META_LANG = 'goride_rider_lang';
    public const CHANNEL_ID = 'goride_rider_updates';

    private const STATUS_EVENTS = [
        'accepted' => 'trip_accepted',
        'arrived_at_pickup' => 'trip_arrived',
        'finished' => 'trip_finished',
    ];

    /** @var callable(string,array<string,string>,array<string,string>):bool */
    private $sender;

    /** @var callable(int):int */
    private $userResolver;

    /**
     * @param callable(string,array<string,string>,array<string,string>):bool $sender    envía un push (token, data, alerta Android)
     * @param callable(int):int                                              $userResolver booking_id => user_id del pasajero (0 si no hay)
     */
    public function __construct(callable $sender, callable $userResolver)
    {
        $this->sender = $sender;
        $this->userResolver = $userResolver;
    }

    public static function normalizeLang(string $lang): string
    {
        return strtolower(substr(trim($lang), 0, 2)) === 'en' ? 'en' : 'es';
    }

    public function saveToken(int $userId, string $token, string $lang = ''): void
    {
        $token = trim($token);
        if ($userId <= 0 || strlen($token) < 20 || strlen($token) > 4096 || preg_match('/^[A-Za-z0-9_:\-.]+$/', $token) !== 1) {
            throw new RiderException('VALIDATION_ERROR');
        }
        // Un mismo teléfono no debe seguir recibiendo avisos de la cuenta anterior.
        $others = get_users(['meta_key' => self::META_TOKEN, 'meta_value' => $token, 'exclude' => [$userId], 'fields' => 'ID']);
        foreach ((array) $others as $other) {
            delete_user_meta((int) $other, self::META_TOKEN);
        }
        update_user_meta($userId, self::META_TOKEN, $token);
        if ($lang !== '') {
            update_user_meta($userId, self::META_LANG, self::normalizeLang($lang));
        }
    }

    public function clearToken(int $userId): void
    {
        if ($userId > 0) {
            delete_user_meta($userId, self::META_TOKEN);
        }
    }

    /** Hook de post meta: _goride_live_status cambió. */
    public function onPostMeta($metaId, $postId, $metaKey, $value): void
    {
        if ($metaKey !== '_goride_live_status') {
            return;
        }
        $status = is_string($value) ? $value : '';
        if (!isset(self::STATUS_EVENTS[$status])) {
            return;
        }
        try {
            $this->notifyStatus((int) $postId, $status);
        } catch (\Throwable $e) {
            error_log('[GORIDE-RIDER] push estado: ' . $e->getMessage());
        }
    }

    /** Hook de la acción goride_chat_message_inserted. */
    public function onChatMessage($bookingId, $sender, $message, $messageId = 0): void
    {
        if ($sender !== 'driver') {
            return;
        }
        try {
            $this->notifyChat((int) $bookingId, (string) $message, (int) $messageId);
        } catch (\Throwable $e) {
            error_log('[GORIDE-RIDER] push chat: ' . $e->getMessage());
        }
    }

    public function notifyStatus(int $bookingId, string $status): bool
    {
        $event = self::STATUS_EVENTS[$status] ?? null;
        if ($event === null || $bookingId <= 0) {
            return false;
        }
        $once = '_goride_rider_push_' . $event;
        if (get_post_meta($bookingId, $once, true) !== '') {
            return false; // ya avisado: evita duplicados si el estado se reescribe
        }
        $userId = (int) ($this->userResolver)($bookingId);
        $token = $userId > 0 ? (string) get_user_meta($userId, self::META_TOKEN, true) : '';
        if ($token === '') {
            return false;
        }
        $lang = self::normalizeLang((string) get_user_meta($userId, self::META_LANG, true));
        [$title, $body] = self::text($event, $lang);
        update_post_meta($bookingId, $once, '1');

        return $this->push($token, [
            'type' => $event,
            'booking_id' => (string) $bookingId,
            'notice_id' => $event . '-' . $bookingId,
        ], $title, $body);
    }

    public function notifyChat(int $bookingId, string $message, int $messageId): bool
    {
        if ($bookingId <= 0 || trim($message) === '') {
            return false;
        }
        $userId = (int) ($this->userResolver)($bookingId);
        $token = $userId > 0 ? (string) get_user_meta($userId, self::META_TOKEN, true) : '';
        if ($token === '') {
            return false;
        }
        $lang = self::normalizeLang((string) get_user_meta($userId, self::META_LANG, true));
        [$title] = self::text('chat_message', $lang);
        $clean = trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($message)));
        $body = function_exists('mb_substr') ? mb_substr($clean, 0, 120) : substr($clean, 0, 120);

        return $this->push($token, [
            'type' => 'chat_message',
            'booking_id' => (string) $bookingId,
            'message_id' => (string) $messageId,
            'notice_id' => 'chat-' . $bookingId . '-' . $messageId,
        ], $title, $body);
    }

    /** @return array{0:string,1:string} */
    public static function text(string $event, string $lang): array
    {
        $en = $lang === 'en';
        switch ($event) {
            case 'trip_accepted':
                return $en ? ['Driver on the way', 'A driver accepted your trip and is heading to you.']
                           : ['Conductor en camino', 'Un conductor aceptó tu viaje y va hacia ti.'];
            case 'trip_arrived':
                return $en ? ['Your driver has arrived', 'Your driver is waiting at the pickup point.']
                           : ['Tu conductor llegó', 'Tu conductor te está esperando en el punto de recogida.'];
            case 'trip_finished':
                return $en ? ['Trip finished', 'Thanks for riding with GoRide!']
                           : ['Viaje finalizado', '¡Gracias por viajar con GoRide!'];
            default:
                return $en ? ['New message from your driver', ''] : ['Nuevo mensaje de tu conductor', ''];
        }
    }

    /** @param array<string,string> $data */
    private function push(string $token, array $data, string $title, string $body): bool
    {
        try {
            return (bool) ($this->sender)($token, $data, ['title' => $title, 'body' => $body, 'channel_id' => self::CHANNEL_ID]);
        } catch (\Throwable $e) {
            error_log('[GORIDE-RIDER] push envío: ' . $e->getMessage());

            return false;
        }
    }
}
