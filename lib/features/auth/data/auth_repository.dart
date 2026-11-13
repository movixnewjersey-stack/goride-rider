import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/session/session.dart';
import '../domain/legal_terms.dart';

abstract class AuthRepository {
  Future<Session> login({required String email, required String password});

  Future<Session> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required bool termsAccepted,
  });
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);

  final ApiClient _api;

  static const String _p = AppConfig.authPrefix;

  @override
  Future<Session> login({required String email, required String password}) async {
    final d = await _api.post(
      '$_p/auth/login',
      body: <String, dynamic>{'email': email, 'password': password},
      auth: false,
    );
    return Session.fromAuthJson(d, email: email);
  }

  @override
  Future<Session> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required bool termsAccepted,
  }) async {
    // Sin la cabecera X-GoRide-App: esa solo la envía la app de conductores.
    final d = await _api.post(
      '$_p/auth/register',
      body: <String, dynamic>{
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'terms_accepted': termsAccepted,
        'terms_version': LegalTerms.termsVersion,
        'privacy_version': LegalTerms.privacyVersion,
      },
      auth: false,
    );
    return Session.fromAuthJson(d, email: email);
  }
}
