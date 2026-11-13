import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

class ActiveTripState {
  const ActiveTripState({
    this.initialized = false,
    this.trip,
    this.recoverError,
    this.connectionLost = false,
    this.cancelling = false,
    this.cancelError,
  });

  /// Ya se intentó recuperar el viaje al abrir la app (con o sin éxito).
  final bool initialized;
  final Trip? trip;
  final String? recoverError;
  final bool connectionLost;
  final bool cancelling;
  final String? cancelError;

  ActiveTripState copyWith({
    bool? initialized,
    Trip? trip,
    bool clearTrip = false,
    String? recoverError,
    bool clearRecoverError = false,
    bool? connectionLost,
    bool? cancelling,
    String? cancelError,
    bool clearCancelError = false,
  }) {
    return ActiveTripState(
      initialized: initialized ?? this.initialized,
      trip: clearTrip ? null : (trip ?? this.trip),
      recoverError: clearRecoverError ? null : (recoverError ?? this.recoverError),
      connectionLost: connectionLost ?? this.connectionLost,
      cancelling: cancelling ?? this.cancelling,
      cancelError: clearCancelError ? null : (cancelError ?? this.cancelError),
    );
  }
}

/// Viaje en curso del pasajero: se RECUPERA del servidor (no de memoria local),
/// se sondea mientras está vivo y sobrevive a cerrar/reabrir la app.
class ActiveTripController extends StateNotifier<ActiveTripState> {
  /// Lectura pública del estado actual (para pruebas).
  ActiveTripState get snapshot => state;

  ActiveTripController(
    this._repo, {
    this.pollInterval = AppConfig.tripPollInterval,
    this.autoPoll = true,
  }) : super(const ActiveTripState());

  final TripRepository _repo;
  final Duration pollInterval;
  final bool autoPoll;

  Timer? _timer;
  bool _refreshing = false;
  int _failures = 0;

  /// Viajes cuyo resumen el pasajero ya cerró: no vuelven a aparecer al recuperar.
  final Set<int> _dismissed = <int>{};

  /// Consulta «mi viaje activo» al servidor. Se llama al iniciar sesión, al
  /// abrir la app y al volver a primer plano.
  Future<void> recover() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      var trip = await _repo.active();
      if (!mounted) {
        return;
      }
      _failures = 0;
      if (trip != null && !trip.isLive && _dismissed.contains(trip.bookingId)) {
        trip = null;
      }
      if (trip == null) {
        // El servidor manda: si ya no hay viaje vivo, se limpia lo local salvo un resumen terminal pendiente de cerrar.
        final keep = state.trip != null && state.trip!.status.isLive == false && state.trip!.isTerminal;
        state = state.copyWith(
          initialized: true,
          clearTrip: !keep,
          clearRecoverError: true,
          connectionLost: false,
        );
      } else {
        state = state.copyWith(
          initialized: true,
          trip: trip,
          clearRecoverError: true,
          connectionLost: false,
        );
      }
      _syncTimer();
    } catch (e) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(initialized: true, recoverError: userMessage(e), connectionLost: true);
    } finally {
      _refreshing = false;
    }
  }

  /// Un viaje recién creado por el servidor.
  void adopt(Trip trip) {
    state = state.copyWith(
      initialized: true,
      trip: trip,
      clearRecoverError: true,
      clearCancelError: true,
      connectionLost: false,
    );
    _syncTimer();
  }

  /// Actualiza el estado y la ubicación del conductor (sondeo corto).
  Future<void> refresh() async {
    final current = state.trip;
    if (current == null || _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final trip = await _repo.trip(current.bookingId);
      if (!mounted) {
        return;
      }
      _failures = 0;
      state = state.copyWith(trip: trip, connectionLost: false);
      _syncTimer();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.statusCode == 404) {
        // El servidor ya no reconoce el viaje como del usuario.
        state = state.copyWith(clearTrip: true, connectionLost: false);
        _syncTimer();
      } else {
        _failures++;
        if (_failures >= 2) {
          state = state.copyWith(connectionLost: true);
        }
      }
    } catch (_) {
      _failures++;
      if (mounted && _failures >= 2) {
        state = state.copyWith(connectionLost: true);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Cancela con validación de estado en el servidor. Seguro contra doble toque.
  Future<void> cancel() async {
    final current = state.trip;
    if (current == null || state.cancelling) {
      return;
    }
    state = state.copyWith(cancelling: true, clearCancelError: true);
    try {
      final result = await _repo.cancel(current.bookingId);
      if (!mounted) {
        return;
      }
      state = state.copyWith(trip: result.trip, cancelling: false);
      _syncTimer();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        cancelling: false,
        cancelError: e.code == 'TRIP_NOT_CANCELABLE'
            ? 'Este viaje ya no se puede cancelar.'
            : (e.outcomeUnknown || e.isNetwork)
                ? 'No pudimos confirmar la cancelación. Revisa el estado del viaje e inténtalo de nuevo.'
                : userMessage(e),
      );
      // Tras un conflicto o un resultado dudoso, el servidor es la fuente de verdad.
      await refresh();
    } catch (e) {
      if (mounted) {
        state = state.copyWith(cancelling: false, cancelError: userMessage(e));
      }
    }
  }

  /// El pasajero cierra el resumen final (viaje terminado o cancelado).
  void dismiss() {
    final id = state.trip?.bookingId;
    if (id != null) {
      _dismissed.add(id);
    }
    state = state.copyWith(clearTrip: true, clearCancelError: true, connectionLost: false);
    _syncTimer();
  }

  /// Limpia todo (cierre de sesión).
  void clear() {
    _timer?.cancel();
    _timer = null;
    _dismissed.clear();
    state = const ActiveTripState();
  }

  void pausePolling() {
    _timer?.cancel();
    _timer = null;
  }

  void resumePolling() => _syncTimer();

  void _syncTimer() {
    final live = state.trip?.isLive ?? false;
    if (!autoPoll || !live) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(pollInterval, (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
