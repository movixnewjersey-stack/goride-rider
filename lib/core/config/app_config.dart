/// Configuración de red. Se puede cambiar al compilar:
/// `flutter run --dart-define=API_BASE=https://otro-sitio/wp-json`
abstract class AppConfig {
  AppConfig._();

  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://goride.website/wp-json',
  );

  /// Namespace de autenticación ya existente en el servidor (goride-api).
  static const String authPrefix = '/goride/v2';

  /// Namespace de la API de pasajeros (plugin goride-rider-api).
  static const String riderPrefix = '/goride-rider/v1';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Intervalo de sondeo del viaje activo (estado + ubicación del conductor).
  static const Duration tripPollInterval = Duration(seconds: 5);

  /// Intervalo de sondeo del chat.
  static const Duration chatPollInterval = Duration(seconds: 4);

  /// Una ubicación del conductor más vieja que esto se marca como desactualizada.
  static const int staleLocationSeconds = 60;

  /// Punto inicial del mapa cuando no hay permiso de ubicación (Newark, NJ).
  static const double defaultLat = 40.7357;
  static const double defaultLng = -74.1724;
}
