import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/session_storage.dart';
import 'session.dart';

enum SessionStatus { unknown, unauthenticated, authenticated }

class SessionState extends Equatable {
  const SessionState._(this.status, this.session);

  const SessionState.unknown() : this._(SessionStatus.unknown, null);
  const SessionState.unauthenticated() : this._(SessionStatus.unauthenticated, null);
  const SessionState.authenticated(Session session) : this._(SessionStatus.authenticated, session);

  final SessionStatus status;
  final Session? session;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  @override
  List<Object?> get props => [status, session];
}

class SessionController extends StateNotifier<SessionState> {
  /// Lectura pública del estado actual (para pruebas).
  SessionState get snapshot => state;

  SessionController(this._storage) : super(const SessionState.unknown());

  final SessionStorage _storage;

  /// Lee la sesión guardada. Una sesión caducada se descarta.
  Future<void> restore() async {
    final saved = await _storage.read();
    if (!mounted) {
      return;
    }
    if (saved == null || saved.isExpired()) {
      if (saved != null) {
        await _storage.clear();
      }
      if (mounted) {
        state = const SessionState.unauthenticated();
      }
      return;
    }
    state = SessionState.authenticated(saved);
  }

  Future<void> signIn(Session session) async {
    await _storage.write(session);
    if (mounted) {
      state = SessionState.authenticated(session);
    }
  }

  Future<void> signOut() async {
    await _storage.clear();
    if (mounted) {
      state = const SessionState.unauthenticated();
    }
  }

  /// El servidor rechazó el token (401): se cierra la sesión local.
  void expire() {
    if (state.isAuthenticated) {
      signOut();
    }
  }
}
