import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_client.dart';
import 'package:goride_rider_app/core/push/push_gateway.dart';
import 'package:goride_rider_app/core/push/push_notice.dart';
import 'package:goride_rider_app/core/push/push_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200});

  int status;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'success': status == 200, 'data': {}}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeGateway implements PushGateway {
  String? currentToken = 'tok-1';
  bool permissionAsked = false;
  bool deleted = false;
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<PushNotice> foreground = StreamController<PushNotice>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionAsked = true;
    return true;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  @override
  Stream<PushNotice> get foregroundMessages => foreground.stream;

  @override
  Future<void> deleteToken() async => deleted = true;
}

PushService _service(_Adapter a, _FakeGateway g, {void Function(PushNotice)? onForeground, String lang = 'es'}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/wp-json'))..httpClientAdapter = a;
  return PushService(
    gateway: g,
    api: ApiClient(dio: dio, readToken: () => 'bearer'),
    language: () => lang,
    onForegroundMessage: onForeground,
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('start pide permiso y registra el token con el idioma', () async {
    final a = _Adapter();
    final g = _FakeGateway();
    final s = _service(a, g, lang: 'en');
    await s.start();
    expect(g.permissionAsked, true);
    expect(a.requests, hasLength(1));
    expect(a.requests.single.path, '/goride-rider/v1/push/token');
    expect(a.requests.single.data, {'token': 'tok-1', 'lang': 'en'});
    await s.stop();
  });

  test('start es idempotente: no registra dos veces', () async {
    final a = _Adapter();
    final s = _service(a, _FakeGateway());
    await s.start();
    await s.start();
    expect(a.requests, hasLength(1));
    await s.stop();
  });

  test('sin token de Firebase no llama al servidor ni falla', () async {
    final a = _Adapter();
    final g = _FakeGateway()..currentToken = null;
    final s = _service(a, g);
    await s.start();
    expect(a.requests, isEmpty);
    await s.stop();
  });

  test('un error del servidor al registrar no lanza', () async {
    final a = _Adapter(status: 500);
    final s = _service(a, _FakeGateway());
    await expectLater(s.start(), completes);
    await s.stop();
  });

  test('cuando Firebase renueva el token se vuelve a registrar', () async {
    final a = _Adapter();
    final g = _FakeGateway();
    final s = _service(a, g);
    await s.start();
    g.refresh.add('tok-2');
    // La petición HTTP simulada termina en otra vuelta del bucle de eventos.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.requests, hasLength(2));
    expect(a.requests.last.data['token'], 'tok-2');
    await s.stop();
  });

  test('un aviso con la app abierta ejecuta el callback', () async {
    var n = 0;
    final g = _FakeGateway();
    final s = _service(_Adapter(), g, onForeground: (_) => n++);
    await s.start();
    g.foreground.add(const PushNotice(title: 't', body: 'b'));
    await _tick();
    expect(n, 1);
    await s.stop();
    g.foreground.add(const PushNotice(title: 't', body: 'b'));
    await _tick();
    expect(n, 1, reason: 'tras stop() ya no escucha');
  });

  test('stop(unregister) avisa al servidor y borra el token del teléfono', () async {
    final a = _Adapter();
    final g = _FakeGateway();
    final s = _service(a, g);
    await s.start();
    await s.stop(unregister: true);
    expect(a.requests.last.path, '/goride-rider/v1/push/token/clear');
    expect(g.deleted, true);
    expect(s.isActive, false);
  });

  test('stop sin unregister no toca el servidor', () async {
    final a = _Adapter();
    final g = _FakeGateway();
    final s = _service(a, g);
    await s.start();
    final before = a.requests.length;
    await s.stop();
    expect(a.requests.length, before);
    expect(g.deleted, false);
  });

  test('si el registro falla, retryIfNeeded lo reintenta; una vez registrado no repite', () async {
    final a = _Adapter(status: 500);
    final s = _service(a, _FakeGateway());
    await s.start();
    expect(a.requests, hasLength(1));
    a.status = 200;
    await s.retryIfNeeded();
    expect(a.requests, hasLength(2), reason: 'reintentó tras el fallo');
    await s.retryIfNeeded();
    expect(a.requests, hasLength(2), reason: 'ya registrado: no repite');
    await s.stop();
  });
}
