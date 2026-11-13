import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../trip/data/trip_repository.dart';
import '../../trip/domain/trip.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

class ChatState {
  const ChatState({
    this.entries = const [],
    this.ready = false,
    this.error,
    this.connectionLost = false,
  });

  final List<ChatEntry> entries;

  /// Ya hay credenciales y se leyó el chat al menos una vez.
  final bool ready;
  final String? error;
  final bool connectionLost;

  ChatState copyWith({
    List<ChatEntry>? entries,
    bool? ready,
    String? error,
    bool clearError = false,
    bool? connectionLost,
  }) {
    return ChatState(
      entries: entries ?? this.entries,
      ready: ready ?? this.ready,
      error: clearError ? null : (error ?? this.error),
      connectionLost: connectionLost ?? this.connectionLost,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  /// Lectura pública del estado actual (para pruebas).
  ChatState get snapshot => state;

  ChatController({
    required this.bookingId,
    required TripRepository trips,
    required ChatRepository chat,
    this.pollInterval = AppConfig.chatPollInterval,
    this.autoPoll = true,
  })  : _trips = trips,
        _chat = chat,
        super(const ChatState());

  static const int maxLength = 500;

  final int bookingId;
  final TripRepository _trips;
  final ChatRepository _chat;
  final Duration pollInterval;
  final bool autoPoll;

  ChatCredentials? _credentials;
  final Map<int, ChatMessage> _server = <int, ChatMessage>{};
  final List<_Pending> _pending = <_Pending>[];
  Timer? _timer;
  bool _polling = false;
  int _lastId = 0;
  int _localSeq = 0;
  bool _credentialsRefreshed = false;

  Future<void> start() async {
    await poll();
    if (autoPoll && mounted) {
      _timer?.cancel();
      _timer = Timer.periodic(pollInterval, (_) => poll());
    }
  }

  Future<bool> _ensureCredentials() async {
    if (_credentials != null) {
      return true;
    }
    try {
      _credentials = await _trips.chatToken(bookingId);
      return true;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: userMessage(e), connectionLost: e is ApiException && e.isNetwork);
      }
      return false;
    }
  }

  /// Lee mensajes nuevos (`after_id`). Seguro de llamar varias veces: nunca duplica.
  Future<void> poll() async {
    if (_polling || !mounted) {
      return;
    }
    _polling = true;
    try {
      if (!await _ensureCredentials()) {
        return;
      }
      for (var page = 0; page < 5; page++) {
        final batch = await _chat.fetch(_credentials!, afterId: _lastId);
        for (final m in batch) {
          if (m.id > 0) {
            _server[m.id] = m;
            if (m.id > _lastId) {
              _lastId = m.id;
            }
            _reconcile(m);
          }
        }
        if (batch.length < 50) {
          break;
        }
      }
      if (mounted) {
        _credentialsRefreshed = false;
        _publish(ready: true, connectionLost: false, clearError: true);
      }
    } on ApiException catch (e) {
      // Token rechazado: se pide uno nuevo una sola vez.
      if ((e.statusCode == 401 || e.statusCode == 403) && !_credentialsRefreshed) {
        _credentialsRefreshed = true;
        _credentials = null;
      }
      if (mounted) {
        state = state.copyWith(connectionLost: true);
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(connectionLost: true);
      }
    } finally {
      _polling = false;
    }
  }

  /// El eco del servidor reemplaza al mensaje local equivalente (mismo texto).
  void _reconcile(ChatMessage m) {
    if (!m.isMine) {
      return;
    }
    final i = _pending.indexWhere((p) => p.text == m.message && p.delivery != ChatDelivery.failed);
    if (i >= 0) {
      _pending.removeAt(i);
    }
  }

  /// Envía un mensaje. NUNCA se reintenta solo: si el resultado es desconocido
  /// queda marcado y es el usuario quien decide reenviar (el POST no es idempotente).
  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || text.length > maxLength) {
      return;
    }
    final p = _Pending('local-${_localSeq++}', text, DateTime.now());
    _pending.add(p);
    _publish();
    await _transmit(p);
  }

  Future<void> resend(String localKey) async {
    final i = _pending.indexWhere((p) => p.key == localKey);
    if (i < 0) {
      return;
    }
    final p = _pending[i];
    if (p.delivery == ChatDelivery.sending || p.delivery == ChatDelivery.awaitingEcho) {
      return;
    }
    p.delivery = ChatDelivery.sending;
    _publish();
    await _transmit(p);
  }

  void discard(String localKey) {
    _pending.removeWhere((p) => p.key == localKey && p.delivery != ChatDelivery.sending);
    _publish();
  }

  Future<void> _transmit(_Pending p) async {
    if (!await _ensureCredentials()) {
      p.delivery = ChatDelivery.failed;
      _publish();
      return;
    }
    try {
      await _chat.send(_credentials!, p.text);
      if (_pending.contains(p)) {
        p.delivery = ChatDelivery.awaitingEcho;
      }
      _publish();
      await poll();
    } on ApiException catch (e) {
      if (_pending.contains(p)) {
        p.delivery = e.outcomeUnknown ? ChatDelivery.unknown : ChatDelivery.failed;
      }
      _publish();
      // Si el mensaje sí llegó, el sondeo siguiente lo reconcilia y desaparece el aviso.
      if (e.outcomeUnknown) {
        unawaited(poll());
      }
    }
  }

  void _publish({bool? ready, bool? connectionLost, bool clearError = false}) {
    if (!mounted) {
      return;
    }
    final ids = _server.keys.toList()..sort();
    final entries = <ChatEntry>[
      for (final id in ids)
        ChatEntry(
          key: 's$id',
          id: id,
          sender: _server[id]!.sender,
          text: _server[id]!.message,
          delivery: ChatDelivery.sent,
          time: _server[id]!.createdAt,
        ),
      for (final p in _pending)
        ChatEntry(key: p.key, sender: 'client', text: p.text, delivery: p.delivery, time: p.at),
    ];
    state = state.copyWith(
      entries: entries,
      ready: ready,
      connectionLost: connectionLost,
      clearError: clearError,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Pending {
  _Pending(this.key, this.text, this.at);

  final String key;
  final String text;
  final DateTime at;
  ChatDelivery delivery = ChatDelivery.sending;
}
