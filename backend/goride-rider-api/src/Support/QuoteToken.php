<?php

declare(strict_types=1);

namespace GoRideRider\Support;

/**
 * Cotización firmada (HMAC-SHA256). El cliente NO puede alterar precio,
 * distancia ni duración: todo se calcula en el servidor y se firma.
 */
final class QuoteToken
{
    public function __construct(private readonly string $secret, private readonly int $ttl = 600)
    {
        if ($secret === '') {
            throw new \InvalidArgumentException('secret vacío');
        }
    }

    /** @param array<string,mixed> $payload */
    public function issue(array $payload, int $now): string
    {
        $payload['iat'] = $now;
        $payload['exp'] = $now + $this->ttl;
        $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $body = self::b64($json);

        return $body . '.' . self::b64(hash_hmac('sha256', $body, $this->secret, true));
    }

    /** @return array<string,mixed> */
    public function verify(string $token, int $userId, int $now): array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 2 || $parts[0] === '' || $parts[1] === '') {
            throw new RiderException('QUOTE_INVALID');
        }
        $expected = self::b64(hash_hmac('sha256', $parts[0], $this->secret, true));
        if (!hash_equals($expected, $parts[1])) {
            throw new RiderException('QUOTE_INVALID');
        }
        $payload = json_decode((string) self::unb64($parts[0]), true);
        if (!is_array($payload) || (int) ($payload['uid'] ?? 0) !== $userId) {
            throw new RiderException('QUOTE_INVALID');
        }
        if ((int) ($payload['exp'] ?? 0) < $now) {
            throw new RiderException('QUOTE_EXPIRED');
        }

        return $payload;
    }

    private static function b64(string $s): string
    {
        return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    }

    private static function unb64(string $s): string|false
    {
        return base64_decode(strtr($s, '-_', '+/'), true);
    }
}
