import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/features/trip/application/request_controller.dart';
import 'package:goride_rider_app/features/trip/domain/trip.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeTripRepository repo;
  late int keySeq;
  late RequestController c;

  setUp(() {
    repo = FakeTripRepository();
    keySeq = 0;
    c = RequestController(repo, keyFactory: () => 'key-${++keySeq}');
  });

  tearDown(() => c.dispose());

  Future<void> ready() async {
    c.setPickup(pickupPoint);
    c.setDropoff(dropoffPoint);
    await settle();
  }

  test('cotiza automáticamente cuando hay recogida y destino', () async {
    await ready();
    expect(c.snapshot.quoteStatus, QuoteStatus.ready);
    expect(c.snapshot.quote!.quoteId, 'q1');
    expect(repo.quoteCalls, 1);
    expect(c.snapshot.canRequest, true);
  });

  test('una respuesta de cotización vieja no pisa a la nueva', () async {
    final first = Completer<Quote>();
    var n = 0;
    repo.onQuote = (_, __, ___) => (++n == 1) ? first.future : Future.value(sampleQuote(id: 'nueva'));
    c.setPickup(pickupPoint);
    c.setDropoff(dropoffPoint); // 1.ª cotización queda en vuelo
    c.setPassengers(2); // 2.ª cotización
    await settle();
    first.complete(sampleQuote(id: 'vieja'));
    await settle();
    expect(c.snapshot.quote!.quoteId, 'nueva');
  });

  test('DOBLE TOQUE: solo una solicitud sale al servidor', () async {
    await ready();
    final gate = Completer<BookingResult>();
    repo.onBook = (_, __) => gate.future;
    final a = c.confirm();
    final b = c.confirm(); // segundo toque inmediato
    await settle();
    expect(repo.bookCalls, 1);
    expect(c.snapshot.bookingStatus, BookingStatus.submitting);
    expect(c.snapshot.canRequest, false);
    gate.complete(BookingResult(trip: sampleTrip(), replayed: false));
    await Future.wait([a, b]);
    expect(repo.bookCalls, 1);
    expect(c.snapshot.bookingStatus, BookingStatus.done);
    expect(c.snapshot.createdTrip!.bookingId, 100);
  });

  test('NUNCA muestra éxito si el servidor falla', () async {
    await ready();
    repo.onBook = (_, __) async => throw apiError('BOOKING_CREATION_FAILED', status: 502, message: 'No se creó');
    await c.confirm();
    expect(c.snapshot.bookingStatus, BookingStatus.error);
    expect(c.snapshot.createdTrip, isNull);
    expect(c.snapshot.bookingError, 'No se creó');
  });

  test('RECONEXIÓN: tras perder la respuesta se reintenta con la MISMA clave', () async {
    await ready();
    var n = 0;
    repo.onBook = (_, __) async {
      if (++n == 1) {
        throw networkUnknown();
      }
      return BookingResult(trip: sampleTrip(), replayed: true);
    };
    await c.confirm();
    expect(c.snapshot.bookingStatus, BookingStatus.error);
    expect(c.snapshot.bookingOutcomeUnknown, true);
    expect(c.snapshot.createdTrip, isNull);
    await c.confirm(); // «Reintentar»
    expect(repo.bookKeys, ['key-1', 'key-1']);
    expect(c.snapshot.bookingStatus, BookingStatus.done);
  });

  test('si cambian los datos, el nuevo intento usa clave NUEVA', () async {
    await ready();
    repo.onBook = (_, __) async => throw networkUnknown();
    await c.confirm();
    c.setPassengers(2);
    await settle();
    repo.onBook = null;
    await c.confirm();
    expect(repo.bookKeys, ['key-1', 'key-2']);
  });

  test('PRICE_CHANGED: muestra el nuevo precio, recotiza y exige reconfirmar con otra clave', () async {
    await ready();
    var cotizaciones = 0;
    repo.onQuote = (_, __, ___) async => sampleQuote(id: 'q${++cotizaciones + 1}', total: 21.0);
    repo.onBook = (_, __) async => throw apiError(
          'PRICE_CHANGED',
          data: {'price': {'total': 21.0}},
        );
    await c.confirm();
    expect(c.snapshot.priceChangedTo, 21.0);
    expect(c.snapshot.bookingStatus, BookingStatus.error);
    expect(c.snapshot.createdTrip, isNull);
    expect(c.snapshot.quote!.priceTotal, 21.0);
    repo.onBook = null;
    await c.confirm();
    expect(repo.bookKeys.length, 2);
    expect(repo.bookKeys.first != repo.bookKeys.last, true);
  });

  test('ACTIVE_TRIP_EXISTS expone el viaje que bloquea', () async {
    await ready();
    repo.onBook = (_, __) async => throw apiError(
          'ACTIVE_TRIP_EXISTS',
          data: {
            'trip': {
              'booking_id': 55,
              'status': 'driver_assigned',
              'pickup': {'lat': 1, 'lng': 2, 'address': 'A'},
              'dropoff': {'lat': 3, 'lng': 4, 'address': 'B'},
              'can_cancel': true,
            },
          },
        );
    await c.confirm();
    expect(c.snapshot.blockingTrip!.bookingId, 55);
    expect(c.snapshot.blockingTrip!.status, TripStatus.driverAssigned);
  });

  test('cotización vencida: no pide, recotiza', () async {
    repo.onQuote = (_, __, ___) async => sampleQuote(expiresAt: DateTime.now().subtract(const Duration(seconds: 1)));
    await ready();
    await c.confirm();
    expect(repo.bookCalls, 0);
    expect(c.snapshot.bookingError, isNotNull);
  });

  test('error de cotización no permite pedir', () async {
    repo.onQuote = (_, __, ___) async => throw apiError('ZONE_NOT_ALLOWED', status: 422, message: 'Fuera de zona');
    await ready();
    expect(c.snapshot.quoteStatus, QuoteStatus.error);
    expect(c.snapshot.quoteError, 'Fuera de zona');
    await c.confirm();
    expect(repo.bookCalls, 0);
  });
}
