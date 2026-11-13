import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

typedef TokenReader = String? Function();

/// Cliente HTTP único hacia el sobre estándar de GoRide:
/// `{ success, code, message, data }`. Devuelve siempre `data` (mapa).
class ApiClient {
  ApiClient({
    Dio? dio,
    required this.readToken,
    this.onUnauthorized,
  }) : _dio = dio ?? _buildDio();

  final Dio _dio;
  final TokenReader readToken;

  /// Se invoca cuando una petición autenticada recibe 401 (sesión caducada o revocada).
  final void Function()? onUnauthorized;

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBase,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.receiveTimeout,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) {
    return _send('GET', path, query: query, auth: auth);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool auth = true,
  }) {
    // El servidor (Mod_Security) exige Content-Type JSON con cuerpo explícito.
    return _send('POST', path, body: body ?? <String, dynamic>{}, headers: headers, auth: auth);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    required bool auth,
  }) async {
    final token = auth ? readToken() : null;
    if (auth && (token == null || token.isEmpty)) {
      throw const ApiException(
        code: 'AUTH_TOKEN_MISSING',
        message: 'Inicia sesión para continuar.',
        statusCode: 401,
      );
    }

    final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: Headers.jsonContentType,
          validateStatus: (_) => true,
          headers: <String, dynamic>{
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            if (token != null) 'Authorization': 'Bearer $token',
            ...?headers,
          },
        ),
      );
    } on DioException catch (e) {
      throw _mapDio(e, isWrite: method != 'GET');
    }

    return _parse(response, auth: auth);
  }

  Map<String, dynamic> _parse(Response<dynamic> response, {required bool auth}) {
    final status = response.statusCode ?? 0;
    final raw = response.data;

    if (raw is! Map) {
      throw ApiException(
        code: ApiException.badResponse,
        message: 'Respuesta inesperada del servidor.',
        statusCode: status,
      );
    }

    final body = Map<String, dynamic>.from(raw);
    final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : <String, dynamic>{};
    final ok = status >= 200 && status < 300 && body['success'] != false;

    if (ok) {
      return data;
    }

    final code = (body['code'] is String && (body['code'] as String).isNotEmpty)
        ? body['code'] as String
        : 'HTTP_$status';
    final error = ApiException(
      code: code,
      message: body['message'] is String ? body['message'] as String : '',
      statusCode: status,
      data: data.isEmpty ? null : data,
    );

    if (status == 401 && auth) {
      onUnauthorized?.call();
    }

    throw error;
  }

  ApiException _mapDio(DioException e, {required bool isWrite}) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const ApiException(code: ApiException.cancelled, message: 'Cancelado.');
      case DioExceptionType.connectionTimeout:
        // Nunca llegó a conectar: la petición no salió.
        return const ApiException(code: ApiException.timeout, message: '');
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        // La petición pudo llegar (o incluso responderse) al servidor: en una
        // escritura NO se puede afirmar que no se ejecutó.
        return ApiException(code: ApiException.timeout, message: '', outcomeUnknown: isWrite);
      case DioExceptionType.connectionError:
        return const ApiException(code: ApiException.networkError, message: '');
      case DioExceptionType.badCertificate:
        return const ApiException(code: ApiException.networkError, message: '');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return ApiException(code: ApiException.networkError, message: '', outcomeUnknown: isWrite);
    }
  }
}
