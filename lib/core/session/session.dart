import 'package:equatable/equatable.dart';

import '../api/api_exception.dart';

/// Sesión del pasajero (token Bearer emitido por goride-api).
class Session extends Equatable {
  const Session({
    required this.token,
    required this.expiresAt,
    required this.userId,
    this.role = '',
    this.email = '',
  });

  factory Session.fromAuthJson(Map<String, dynamic> data, {String email = ''}) {
    final token = data['access_token'];
    final user = data['user'];
    if (token is! String || token.isEmpty || user is! Map) {
      throw const ApiException(
        code: ApiException.badResponse,
        message: 'Respuesta de inicio de sesión incompleta.',
      );
    }
    final expires = DateTime.tryParse('${data['expires_at'] ?? ''}');
    return Session(
      token: token,
      expiresAt: expires ?? DateTime.now().add(const Duration(hours: 12)),
      userId: int.tryParse('${user['id']}') ?? 0,
      role: '${user['role'] ?? ''}',
      email: email,
    );
  }

  factory Session.fromStorage(Map<String, dynamic> json) {
    return Session(
      token: '${json['token']}',
      expiresAt: DateTime.tryParse('${json['expires_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      userId: int.tryParse('${json['user_id']}') ?? 0,
      role: '${json['role'] ?? ''}',
      email: '${json['email'] ?? ''}',
    );
  }

  final String token;
  final DateTime expiresAt;
  final int userId;
  final String role;
  final String email;

  bool isExpired([DateTime? now]) => !expiresAt.isAfter(now ?? DateTime.now());

  Map<String, dynamic> toStorage() => <String, dynamic>{
        'token': token,
        'expires_at': expiresAt.toIso8601String(),
        'user_id': userId,
        'role': role,
        'email': email,
      };

  @override
  List<Object?> get props => [token, expiresAt, userId, role, email];
}
