import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_notice.dart';

/// Acceso a Firebase Cloud Messaging, aislado para poder probar el resto sin Firebase.
abstract class PushGateway {
  /// Pide permiso de notificaciones (Android 13+). Devuelve si fue concedido.
  Future<bool> requestPermission();

  /// Token FCM de este teléfono, o null si no está disponible.
  Future<String?> token();

  /// Nuevo token cuando Firebase lo renueva.
  Stream<String> get tokenRefresh;

  /// Un aviso llegó con la app abierta.
  Stream<PushNotice> get foregroundMessages;

  /// Invalida el token de este teléfono (al cerrar sesión).
  Future<void> deleteToken();
}

/// Implementación real. Si Firebase no se pudo iniciar (por ejemplo falta
/// google-services.json), nada falla: simplemente no hay avisos push.
class FirebasePushGateway implements PushGateway {
  bool get _ready => Firebase.apps.isNotEmpty;

  @override
  Future<bool> requestPermission() async {
    if (!_ready) {
      return false;
    }
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> token() async {
    if (!_ready) {
      return null;
    }
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefresh => _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream<String>.empty();

  @override
  Stream<PushNotice> get foregroundMessages => _ready
      ? FirebaseMessaging.onMessage.map(
          (m) => PushNotice(title: m.notification?.title ?? '', body: m.notification?.body ?? ''),
        )
      : const Stream<PushNotice>.empty();

  @override
  Future<void> deleteToken() async {
    if (!_ready) {
      return;
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
