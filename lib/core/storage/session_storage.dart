import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../session/session.dart';

abstract class SessionStorage {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

/// Guarda la sesión cifrada (Keystore de Android). Nunca en SharedPreferences.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _key = 'goride_rider_session';
  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return Session.fromStorage(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Session session) => _storage.write(key: _key, value: jsonEncode(session.toStorage()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Para pruebas.
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this.value]);

  Session? value;

  @override
  Future<Session?> read() async => value;

  @override
  Future<void> write(Session session) async => value = session;

  @override
  Future<void> clear() async => value = null;
}
