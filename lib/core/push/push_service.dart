import 'dart:async';

import '../api/api_client.dart';
import '../config/app_config.dart';
import 'push_gateway.dart';

/// Registra el token FCM del teléfono en el servidor mientras haya sesión,
/// para que el servidor avise al pasajero (conductor aceptó / llegó / viaje
/// finalizado / mensaje del conductor). Nunca lanza: un fallo de avisos no
/// debe afectar al resto de la app.
class PushService {
  PushService({
    required PushGateway gateway,
    required ApiClient api,
    required String Function() language,
    void Function()? onForegroundMessage,
  })  : _gateway = gateway,
        _api = api,
        _language = language,
        _onForegroundMessage = onForegroundMessage;

  final PushGateway _gateway;
  final ApiClient _api;
  final String Function() _language;
  final void Function()? _onForegroundMessage;

  static const String _p = AppConfig.riderPrefix;

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<void>? _foregroundSub;
  bool _active = false;

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
    _foregroundSub = _gateway.foregroundMessages.listen((_) => _onForegroundMessage?.call());
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
    } catch (_) {}
  }
}
