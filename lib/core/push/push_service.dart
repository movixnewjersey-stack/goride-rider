import 'dart:async';

import '../api/api_client.dart';
import '../config/app_config.dart';
import 'push_gateway.dart';
import 'push_notice.dart';

/// Registra el token FCM del teléfono en el servidor mientras haya sesión,
/// para que el servidor avise al pasajero (conductor aceptó / llegó / viaje
/// finalizado / mensaje del conductor). Nunca lanza: un fallo de avisos no
/// debe afectar al resto de la app.
class PushService {
  PushService({
    required PushGateway gateway,
    required ApiClient api,
    required String Function() language,
    void Function(PushNotice notice)? onForegroundMessage,
  })  : _gateway = gateway,
        _api = api,
        _language = language,
        _onForegroundMessage = onForegroundMessage;

  final PushGateway _gateway;
  final ApiClient _api;
  final String Function() _language;
  final void Function(PushNotice notice)? _onForegroundMessage;

  static const String _p = AppConfig.riderPrefix;

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<PushNotice>? _foregroundSub;
  bool _active = false;
  bool _registered = false;

  bool get isActive => _active;

  /// Empieza a registrar el token (idempotente).
  Future<void> start() async {
    if (_active) {
      return;
    }
    _active = true;
    try {
      await _gateway.requestPermission();
      final token = await _gateway.token();
      if (token != null && token.isNotEmpty) {
        await _register(token);
      }
    } catch (_) {}
    if (!_active) {
      return;
    }
    _refreshSub = _gateway.tokenRefresh.listen((t) => unawaited(_register(t)));
    _foregroundSub = _gateway.foregroundMessages.listen((n) => _onForegroundMessage?.call(n));
  }

  /// Si el último registro no llegó al servidor (sin red, plugin inactivo…), lo reintenta.
  Future<void> retryIfNeeded() async {
    if (_active && !_registered) {
      await refresh();
    }
  }

  /// Vuelve a enviar el token (p. ej. si cambió el idioma elegido).
  Future<void> refresh() async {
    if (!_active) {
      return;
    }
    final token = await _gateway.token();
    if (token != null && token.isNotEmpty) {
      await _register(token);
    }
  }

  /// Deja de escuchar. Con [unregister] también quita el token del servidor
  /// (hay que llamarlo ANTES de borrar la sesión, porque usa el Bearer).
  Future<void> stop({bool unregister = false}) async {
    _active = false;
    _registered = false;
    await _refreshSub?.cancel();
    await _foregroundSub?.cancel();
    _refreshSub = null;
    _foregroundSub = null;
    if (unregister) {
      try {
        await _api.post('$_p/push/token/clear');
      } catch (_) {}
      await _gateway.deleteToken();
    }
  }

  Future<void> _register(String token) async {
    try {
      await _api.post('$_p/push/token', body: <String, dynamic>{'token': token, 'lang': _language()});
      _registered = true;
    } catch (_) {
      _registered = false;
    }
  }
}
