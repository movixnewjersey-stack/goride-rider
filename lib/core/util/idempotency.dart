import 'dart:math';

/// Clave de idempotencia: 32 caracteres hexadecimales aleatorios (cumple
/// `[A-Za-z0-9_-]{8,64}` del contrato). Se genera UNA vez por intento del
/// usuario y se reutiliza en los reintentos de ese mismo intento.
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Sesión de búsqueda de direcciones (agrupa la facturación de Google).
String newSearchSession([Random? random]) => newIdempotencyKey(random).substring(0, 16);
