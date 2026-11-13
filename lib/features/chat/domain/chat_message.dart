import 'package:equatable/equatable.dart';

/// Mensaje tal como lo devuelve el chat existente (`goride/v1/chat`).
class ChatMessage extends Equatable {
  const ChatMessage({required this.id, required this.sender, required this.message, this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: int.tryParse('${j['id']}') ?? 0,
        sender: '${j['sender'] ?? ''}',
        message: '${j['message'] ?? ''}',
        createdAt: parseServerTime('${j['created_at'] ?? ''}'),
      );

  final int id;
  final String sender;
  final String message;
  final DateTime? createdAt;

  bool get isMine => sender == 'client';
  bool get isSystem => sender == 'system';

  @override
  List<Object?> get props => [id, sender, message, createdAt];
}

/// `created_at` llega en UTC (`Y-m-d H:i:s`). Devuelve hora local o null.
DateTime? parseServerTime(String raw) {
  if (raw.isEmpty) {
    return null;
  }
  final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(raw);
  final iso = raw.replaceFirst(' ', 'T');
  return DateTime.tryParse(hasZone ? iso : '${iso}Z')?.toLocal();
}

enum ChatDelivery { sent, sending, awaitingEcho, failed, unknown }

/// Línea visible en pantalla: un mensaje del servidor o uno local pendiente.
class ChatEntry extends Equatable {
  const ChatEntry({
    required this.key,
    required this.sender,
    required this.text,
    required this.delivery,
    this.id,
    this.time,
  });

  final String key;
  final int? id;
  final String sender;
  final String text;
  final ChatDelivery delivery;
  final DateTime? time;

  bool get isMine => sender == 'client';
  bool get isSystem => sender == 'system';

  @override
  List<Object?> get props => [key, id, sender, text, delivery, time];
}
