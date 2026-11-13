import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_client.dart';
import 'package:goride_rider_app/core/api/api_exception.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ApiClient _client(_Adapter adapter, {String? token = 't0k', void Function()? onUnauthorized}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/wp-json'))..httpClientAdapter = adapter;
  return ApiClient(dio: dio, readToken: () => token, onUnauthorized: onUnauthorized);
}

void main() {
  test('devuelve data del sobre y envía Bearer', () async {
    final a = _Adapter((_) async => _json({'success': true, 'data': {'x': 1}}, 200));
    final data = await _client(a).get('/ping');
    expect(data['x'], 1);
    expect(a.requests.single.headers['Authorization'], 'Bearer t0k');
  });

  test('POST sin cuerpo envía JSON {} (Mod_Security)', () async {
    final a = _Adapter((_) async => _json({'success': true, 'data': {}}, 200));
    await _client(a).post('/x');
    expect(a.requests.single.data, <String, dynamic>{});
    expect(a.requests.single.contentType, contains('application/json'));
  });

  test('error del servidor conserva código, estado y data', () async {
    final a = _Adapter(
      (_) async => _json({'success': false, 'code': 'PRICE_CHANGED', 'message': 'Cambió', 'data': {'price': {'total': 20}}}, 409),
    );
    try {
      await _client(a).post('/b');
      fail('debía lanzar');
    } on ApiException catch (e) {
      expect(e.code, 'PRICE_CHANGED');
      expect(e.statusCode, 409);
      expect(e.message, 'Cambió');
      expect((e.data!['price'] as Map)['total'], 20);
    }
  });

  test('401 autenticado avisa a la sesión; 401 de login no', () async {
    var calls = 0;
    final a = _Adapter((_) async => _json({'success': false, 'code': 'AUTH_INVALID_TOKEN', 'message': 'no'}, 401));
    final c = _client(a, onUnauthorized: () => calls++);
    await expectLater(c.get('/me'), throwsA(isA<ApiException>()));
    expect(calls, 1);
    await expectLater(c.post('/auth/login', auth: false), throwsA(isA<ApiException>()));
    expect(calls, 1);
  });

  test('sin token no sale ninguna petición', () async {
    final a = _Adapter((_) async => _json({'success': true, 'data': {}}, 200));
    await expectLater(
      _client(a, token: null).get('/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_TOKEN_MISSING')),
    );
    expect(a.requests, isEmpty);
  });

  test('HTML del servidor (p. ej. firewall) => BAD_RESPONSE, sin mostrar el HTML', () async {
    final a = _Adapter(
      (_) async => ResponseBody.fromString(
        '<html>403</html>',
        403,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      ),
    );
    await expectLater(
      _client(a).get('/x'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.badResponse)),
    );
  });

  test('timeout de respuesta en POST => resultado desconocido; en GET no', () async {
    final a = _Adapter(
      (o) async => throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout),
    );
    final c = _client(a);
    await expectLater(
      c.post('/bookings'),
      throwsA(isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true)),
    );
    await expectLater(
      c.get('/trips/1'),
      throwsA(isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', false)),
    );
  });

  test('sin conexión (la petición no salió) => NETWORK_ERROR sin ambigüedad', () async {
    final a = _Adapter(
      (o) async => throw DioException(requestOptions: o, type: DioExceptionType.connectionError),
    );
    await expectLater(
      _client(a).post('/bookings'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.networkError)
            .having((e) => e.outcomeUnknown, 'unknown', false),
      ),
    );
  });

  group('timeouts', () {
    for (final type in <DioExceptionType>[
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
    ]) {
      test('$type: escritura => resultado desconocido y UNA sola petición (sin reintento ciego)', () async {
        final a = _Adapter((o) async => throw DioException(requestOptions: o, type: type));
        await expectLater(
          _client(a).post('/goride-rider/v1/bookings'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', ApiException.timeout)
                .having((e) => e.outcomeUnknown, 'unknown', true),
          ),
        );
        expect(a.requests.length, 1);
      });

      test('$type: lectura => timeout sin ambigüedad', () async {
        final a = _Adapter((o) async => throw DioException(requestOptions: o, type: type));
        await expectLater(
          _client(a).get('/goride-rider/v1/trips/1'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', ApiException.timeout)
                .having((e) => e.outcomeUnknown, 'unknown', false),
          ),
        );
        expect(a.requests.length, 1);
      });
    }

    test('connectionTimeout en escritura: la petición nunca salió => no es ambiguo', () async {
      final a = _Adapter((o) async => throw DioException(requestOptions: o, type: DioExceptionType.connectionTimeout));
      await expectLater(
        _client(a).post('/goride-rider/v1/bookings'),
        throwsA(isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', false)),
      );
    });
  });
}
