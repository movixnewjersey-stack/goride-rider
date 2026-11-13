import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_client.dart';
import 'package:goride_rider_app/features/auth/data/auth_repository.dart';
import 'package:goride_rider_app/features/auth/domain/legal_terms.dart';

class _Capture implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {
          'access_token': 'abc',
          'token_type': 'Bearer',
          'expires_at': '2099-01-01T00:00:00+00:00',
          'user': {'id': 9, 'role': 'customer', 'driver_id': null, 'client_id': null},
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Capture adapter;
  late ApiAuthRepository repo;

  setUp(() {
    adapter = _Capture();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/wp-json'))..httpClientAdapter = adapter;
    repo = ApiAuthRepository(ApiClient(dio: dio, readToken: () => null));
  });

  test('login usa la ruta v2 existente y construye la sesión', () async {
    final s = await repo.login(email: 'a@b.co', password: 'secreto123');
    expect(adapter.last!.path, '/goride/v2/auth/login');
    expect(adapter.last!.headers.containsKey('Authorization'), false);
    expect(s.token, 'abc');
    expect(s.userId, 9);
    expect(s.isExpired(), false);
  });

  test('registro marcado envía terms_accepted=true y las versiones vigentes', () async {
    await repo.register(
      firstName: 'Ana',
      lastName: 'Pérez',
      email: 'a@b.co',
      phone: '+19735550100',
      password: 'secreto123',
      termsAccepted: true,
    );
    final body = Map<String, dynamic>.from(adapter.last!.data as Map);
    expect(adapter.last!.path, '/goride/v2/auth/register');
    expect(body['terms_accepted'], true);
    expect(body['terms_version'], LegalTerms.termsVersion);
    expect(body['privacy_version'], LegalTerms.privacyVersion);
    expect(adapter.last!.headers.containsKey('X-GoRide-App'), false, reason: 'esa cabecera es solo de conductores');
  });

  test('sin marcar jamás concede el consentimiento por su cuenta', () async {
    await repo.register(
      firstName: 'Ana',
      lastName: 'Pérez',
      email: 'a@b.co',
      phone: '+19735550100',
      password: 'secreto123',
      termsAccepted: false,
    );
    final body = Map<String, dynamic>.from(adapter.last!.data as Map);
    expect(body['terms_accepted'], false);
  });
}
