import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';

abstract class AccountRepository {
  /// Elimina la cuenta en el servidor (exige la contraseña). Lanza ApiException si falla.
  Future<void> deleteAccount({required String password});
}

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> deleteAccount({required String password}) async {
    // Endpoint ya instalado en el servidor (mismo que usa GoRide Driver).
    // Una contraseña incorrecta responde 401: NO debe cerrar la sesión por sí sola.
    await _api.post(
      '${AppConfig.authPrefix}/account/delete',
      body: <String, dynamic>{'password': password},
      expireSessionOn401: false,
    );
  }
}
