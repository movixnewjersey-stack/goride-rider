import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/features/chat/domain/chat_message.dart';
import 'package:goride_rider_app/features/trip/domain/trip.dart';

void main() {
  test('Trip.fromJson lee el contrato completo', () {
    final t = Trip.fromJson(const <String, dynamic>{
      'booking_id': 24310,
      'status': 'driver_assigned',
      'pickup': {'lat': '40.7357', 'lng': -74.1724, 'address': 'Newark'},
      'dropoff': {'lat': 40.7128, 'lng': -74.0060, 'address': 'NYC'},
      'price': {'total': 18.45, 'currency': 'USD'},
      'driver': {'id': 12, 'first_name': 'Carlos', 'photo_url': 'https://x/y.jpg'},
      'driver_location': {'lat': 40.7, 'lng': -74.1, 'age_seconds': 75},
      'can_cancel': true,
      'is_terminal': false,
    });
    expect(t.bookingId, 24310);
    expect(t.status, TripStatus.driverAssigned);
    expect(t.pickup.lat, 40.7357);
    expect(t.driver!.firstName, 'Carlos');
    expect(t.locationIsStale, true);
    expect(t.isLive, true);
  });

  test('estados desconocidos no rompen la app', () {
    expect(TripStatus.parse('algo_nuevo'), TripStatus.unknown);
    expect(TripStatus.parse(null), TripStatus.unknown);
    expect(TripStatus.unknown.isLive, false);
  });

  test('driver y ubicación nulos', () {
    final t = Trip.fromJson(const <String, dynamic>{
      'booking_id': 1,
      'status': 'searching',
      'pickup': {'lat': 1, 'lng': 2, 'address': 'a'},
      'dropoff': {'lat': 3, 'lng': 4, 'address': 'b'},
      'price': null,
      'driver': null,
      'driver_location': null,
    });
    expect(t.driver, isNull);
    expect(t.driverLocation, isNull);
    expect(t.priceTotal, isNull);
    expect(t.locationIsStale, false);
  });

  test('la hora de los mensajes llega en UTC y se muestra local', () {
    final t = parseServerTime('2026-10-23 14:10:00')!;
    expect(t.toUtc().hour, 14);
    expect(t.isUtc, false);
    expect(parseServerTime(''), isNull);
  });
}
