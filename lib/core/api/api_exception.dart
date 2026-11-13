/// Error de la API ya normalizado. La UI nunca ve DioException.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.data,
    this.outcomeUnknown = false,
  });

  static const String networkError = 'NETWORK_ERROR';
  static const String timeout = 'TIMEOUT';
  static const String badResponse = 'BAD_RESPONSE';
  static const String cancelled = 'CANCELLED';

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? data;

  /// `true` si la petición pudo llegar al servidor pero no conocemos el
  /// resultado (se cortó la respuesta). Un POST con este indicador NO debe
  /// darse por fallido ni reintentarse a ciegas.
  final bool outcomeUnknown;

  bool get isNetwork => code == networkError || code == timeout;
  bool get isAuth => statusCode == 401;

  @override
  String toString() => 'ApiException($code, http=$statusCode): $message';
}

/// Texto en español para mostrar al usuario.
String userMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case ApiException.networkError:
        return 'Sin conexión con GoRide. Revisa tu internet e inténtalo de nuevo.';
      case ApiException.timeout:
        return 'El servidor tardó demasiado en responder.';
      case ApiException.badResponse:
        return 'Respuesta inesperada del servidor. Inténtalo en unos minutos.';
      default:
        return error.message.isNotEmpty ? error.message : 'Ocurrió un error inesperado.';
    }
  }
  return 'Ocurrió un error inesperado.';
}
