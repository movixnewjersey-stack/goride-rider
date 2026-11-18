import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_client.dart';
import 'package:goride_rider_app/core/api/api_exception.dart';
import 'package:goride_rider_app/features/auth/data/account_repository.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiAccountRepository _repo(_Adapter a, void Function() onUnauthorized) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/wp-json'))..httpClientAdapter = a;
  return ApiAccountRepository(ApiClient(dio: dio, readToken: () => 'tok', onUnauthorized: onUnauthorized));
}

void main() {
  test('envía la contraseña a /goride/v2/account/delete', () async {
    final a = _Adapter(200, {'success': true, 'message': 'Cuenta eliminada.'});
    await _repo(a, () {}).deleteAccount(password: 'secreta');
    expect(a.requests.single.path, '/goride/v2/account/delete');
    expect(a.requests.single.data, {'password': 'secreta'});
    expect(a.requests.single.headers['Authorization'], 'Bearer tok');
  });

  test('contraseña incorrecta (401) lanza el error sin cerrar la sesión', () async {
    var expired = 0;
    final a = _Adapter(401, {'success': false, 'code': 'AUTH_INVALID_CREDENTIALS', 'message': 'La contraseña es incorrecta.'});
    await expectLater(
      _repo(a, () => expired++).deleteAccount(password: 'mala'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AUTH_INVALID_CREDENTIALS')),
    );
    expect(expired, 0);
  });
}
