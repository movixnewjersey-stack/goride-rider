import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/features/trip/application/active_trip_controller.dart';
import 'package:goride_rider_app/features/trip/domain/trip.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeTripRepository repo;
  late ActiveTripController c;

  setUp(() {
    repo = FakeTripRepository();
    c = ActiveTripController(repo, autoPoll: false);
  });

  tearDown(() => c.dispose());

  test('RECUPERACIÓN: al reabrir, el viaje en curso sale del servidor', () async {
    repo.onActive = () async => sampleTrip(id: 321, status: TripStatus.driverAssigned);
    expect(c.snapshot.initialized, false);
    await c.recover();
    expect(c.snapshot.initialized, true);
    expect(c.snapshot.trip!.bookingId, 321);
    expect(c.snapshot.trip!.status, TripStatus.driverAssigned);
  });

  test('sin viaje en el servidor: inicializa y no inventa uno', () async {
    await c.recover();
    expect(c.snapshot.initialized, true);
    expect(c.snapshot.trip, isNull);
  });

  test('si no hay red al abrir: inicializa (no se queda cargando) y avisa', () async {
    repo.onActive = () async => throw networkUnknown();
    await c.recover();
    expect(c.snapshot.initialized, true);
    expect(c.snapshot.recoverError, isNotNull);
    expect(c.snapshot.trip, isNull);
    // al volver la red se recupera
    repo.onActive = () async => sampleTrip(id: 9);
    await c.recover();
    expect(c.snapshot.trip!.bookingId, 9);
    expect(c.snapshot.recoverError, isNull);
  });

  test('el servidor manda: si ya no hay viaje vivo, se limpia el local', () async {
    c.adopt(sampleTrip(id: 5));
    await c.recover(); // active() => null
    expect(c.snapshot.trip, isNull);
  });

  test('un resumen terminal pendiente de cerrar se conserva al volver a primer plano', () async {
    c.adopt(sampleTrip(id: 5, status: TripStatus.finished, canCancel: false, isTerminal: true));
    await c.recover();
    expect(c.snapshot.trip!.status, TripStatus.finished);
    c.dismiss();
    expect(c.snapshot.trip, isNull);
  });

  test('un viaje sin conductores ya cerrado no reaparece', () async {
    final t = sampleTrip(id: 8, status: TripStatus.noDrivers);
    repo.onActive = () async => t;
    await c.recover();
    expect(c.snapshot.trip!.bookingId, 8);
    c.dismiss();
    await c.recover();
    expect(c.snapshot.trip, isNull);
  });

  test('RECONEXIÓN: dos fallos seguidos marcan sin conexión; el siguiente éxito lo limpia', () async {
    c.adopt(sampleTrip(id: 1));
    repo.onTrip = (_) async => throw networkUnknown();
    await c.refresh();
    expect(c.snapshot.connectionLost, false);
    await c.refresh();
    expect(c.snapshot.connectionLost, true);
    expect(c.snapshot.trip!.bookingId, 1, reason: 'conserva el último estado conocido');
    repo.onTrip = (id) async => sampleTrip(id: id, status: TripStatus.driverAssigned);
    await c.refresh();
    expect(c.snapshot.connectionLost, false);
    expect(c.snapshot.trip!.status, TripStatus.driverAssigned);
  });

  test('404 en el sondeo: el servidor ya no reconoce el viaje', () async {
    c.adopt(sampleTrip(id: 1));
    repo.onTrip = (_) async => throw apiError('TRIP_NOT_FOUND', status: 404);
    await c.refresh();
    expect(c.snapshot.trip, isNull);
  });

  test('CANCELAR con doble toque: una sola llamada', () async {
    c.adopt(sampleTrip(id: 1));
    final gate = Completer<CancelResult>();
    repo.onCancel = (_) => gate.future;
    final a = c.cancel();
    final b = c.cancel();
    await settle();
    expect(repo.cancelCalls, 1);
    expect(c.snapshot.cancelling, true);
    gate.complete(
      CancelResult(
        trip: sampleTrip(id: 1, status: TripStatus.cancelled, canCancel: false, isTerminal: true),
        alreadyCancelled: false,
      ),
    );
    await Future.wait([a, b]);
    expect(c.snapshot.cancelling, false);
    expect(c.snapshot.trip!.status, TripStatus.cancelled);
  });

  test('cancelar un viaje ya finalizado (409): mensaje claro y estado real del servidor', () async {
    c.adopt(sampleTrip(id: 1, status: TripStatus.driverAssigned));
    repo.onCancel = (_) async => throw apiError('TRIP_NOT_CANCELABLE');
    repo.onTrip = (id) async => sampleTrip(id: id, status: TripStatus.finished, canCancel: false, isTerminal: true);
    await c.cancel();
    expect(c.snapshot.cancelError, 'Este viaje ya no se puede cancelar.');
    expect(c.snapshot.trip!.status, TripStatus.finished);
    expect(c.snapshot.cancelling, false);
  });

  test('cancelación con resultado desconocido: no afirma que se canceló y consulta al servidor', () async {
    c.adopt(sampleTrip(id: 1));
    repo.onCancel = (_) async => throw networkUnknown();
    await c.cancel();
    expect(c.snapshot.cancelError, contains('No pudimos confirmar'));
    expect(repo.tripCalls, 1);
    expect(c.snapshot.trip!.status, TripStatus.searching);
  });

  test('clear() deja todo como al iniciar (cierre de sesión)', () async {
    c.adopt(sampleTrip(id: 1));
    c.clear();
    expect(c.snapshot.trip, isNull);
    expect(c.snapshot.initialized, false);
  });
}
