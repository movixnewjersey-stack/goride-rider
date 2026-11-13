import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../trip/domain/trip.dart';
import '../domain/chat_message.dart';

abstract class ChatRepository {
  Future<List<ChatMessage>> fetch(ChatCredentials credentials, {required int afterId});

  /// Lanza [ApiException]. Con `outcomeUnknown=true` NO se sabe si el mensaje llegó.
  Future<void> send(ChatCredentials credentials, String text);
}

/// Usa las rutas EXISTENTES `goride/v1/chat` con el token que el servidor
/// entrega solo al dueño del viaje (`/trips/{id}/chat-token`).
class HttpChatRepository implements ChatRepository {
  HttpChatRepository([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                sendTimeout: AppConfig.receiveTimeout,
              ),
            );

  final Dio _dio;

  /// El token solo se envía al mismo servidor de la API, nunca a otro host.
  Uri _endpoint(ChatCredentials c) {
    final base = Uri.parse(c.baseUrl);
    final api = Uri.parse(AppConfig.apiBase);
    if (base.scheme != api.scheme || base.host != api.host) {
      throw const ApiException(code: 'CHAT_TOKEN_UNAVAILABLE', message: 'El chat no está disponible por ahora.');
    }
    return Uri.parse('${c.baseUrl}/chat');
  }

  @override
  Future<List<ChatMessage>> fetch(ChatCredentials credentials, {required int afterId}) async {
    final url = _endpoint(credentials);
    final Response<dynamic> res;
    try {
      res = await _dio.getUri<dynamic>(
        url.replace(
          queryParameters: <String, String>{
            'booking_id': '${credentials.bookingId}',
            'token': credentials.token,
            'after_id': '$afterId',
          },
        ),
        options: Options(validateStatus: (_) => true, headers: const {'Cache-Control': 'no-cache'}),
      );
    } on DioException {
      throw const ApiException(code: ApiException.networkError, message: '');
    }
    final body = res.data;
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300 || body is! Map || body['ok'] != true) {
      throw ApiException(code: 'CHAT_ERROR', message: 'No se pudo leer el chat.', statusCode: status);
    }
    return (body['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<void> send(ChatCredentials credentials, String text) async {
    final url = _endpoint(credentials);
    final Response<dynamic> res;
    try {
      res = await _dio.postUri<dynamic>(
        url,
        data: <String, dynamic>{
          'booking_id': credentials.bookingId,
          'token': credentials.token,
          'sender': 'client',
          'message': text,
        },
        options: Options(contentType: Headers.jsonContentType, validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      // connectionError/connectionTimeout: la petición no salió. El resto: resultado desconocido.
      final notSent = e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;
      throw ApiException(code: ApiException.networkError, message: '', outcomeUnknown: !notSent);
    }
    final body = res.data;
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300 || body is! Map || body['ok'] != true) {
      throw ApiException(code: 'CHAT_ERROR', message: 'No se pudo enviar el mensaje.', statusCode: status);
    }
  }
}
