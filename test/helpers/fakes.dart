import 'dart:async';

import 'package:goride_rider_app/core/api/api_exception.dart';
import 'package:goride_rider_app/core/session/session.dart';
import 'package:goride_rider_app/features/auth/data/auth_repository.dart';
import 'package:goride_rider_app/features/chat/data/chat_repository.dart';
import 'package:goride_rider_app/features/chat/domain/chat_message.dart';
import 'package:goride_rider_app/features/trip/data/trip_repository.dart';
import 'package:goride_rider_app/features/trip/domain/trip.dart';

const pickupPoint = GeoPoint(lat: 40.7357, lng: -74.1724, address: 'Newark, NJ');
const dropoffPoint = GeoPoint(lat: 40.7128, lng: -74.0060, address: 'New York, NY');

Quote sampleQuote({String id = 'q1', double total = 18.45, DateTime? expiresAt}) => Quote(
      quoteId: id,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 10)),
      priceTotal: total,
      currency: 'USD',
      priceFormatted: '\$${total.toStringAsFixed(2)}',
      distanceKm: 12.3,
      durationMin: 25,
      passengers: 1,
    );

Trip sampleTrip({
  int id = 100,
  TripStatus status = TripStatus.searching,
  bool canCancel = true,
  bool isTerminal = false,
  TripDriver? driver,
}) =>
    Trip(
      bookingId: id,
      status: status,
      pickup: pickupPoint,
      dropoff: dropoffPoint,
      priceTotal: 18.45,
      canCancel: canCancel,
      isTerminal: isTerminal,
      driver: driver,
    );

class FakeTripRepository implements TripRepository {
  Future<Quote> Function(GeoPoint pickup, GeoPoint dropoff, int passengers)? onQuote;
  Future<BookingResult> Function(String quoteId, String key)? onBook;
  Future<Trip?> Function()? onActive;
  Future<Trip> Function(int id)? onTrip;
  Future<CancelResult> Function(int id)? onCancel;
  Future<ChatCredentials> Function(int id)? onChatToken;

  int quoteCalls = 0;
  int bookCalls = 0;
  int activeCalls = 0;
  int tripCalls = 0;
  int cancelCalls = 0;
  final List<String> bookKeys = <String>[];

  @override
  Future<ServiceConfig> config() async => const ServiceConfig(ready: true, maxPassengers: 4);

  @override
  Future<Quote> quote({required GeoPoint pickup, required GeoPoint dropoff, required int passengers}) {
    quoteCalls++;
    return (onQuote ?? (_, __, ___) async => sampleQuote())(pickup, dropoff, passengers);
  }

  @override
  Future<BookingResult> book({required String quoteId, required String idempotencyKey}) {
    bookCalls++;
    bookKeys.add(idempotencyKey);
    return (onBook ?? (_, __) async => BookingResult(trip: sampleTrip(), replayed: false))(quoteId, idempotencyKey);
  }

  @override
  Future<Trip?> active() {
    activeCalls++;
    return (onActive ?? () async => null)();
  }

  @override
  Future<Trip> trip(int bookingId) {
    tripCalls++;
    return (onTrip ?? (id) async => sampleTrip(id: id))(bookingId);
  }

  @override
  Future<CancelResult> cancel(int bookingId) {
    cancelCalls++;
    return (onCancel ??
        (id) async => CancelResult(
              trip: sampleTrip(id: id, status: TripStatus.cancelled, canCancel: false, isTerminal: true),
              alreadyCancelled: false,
            ))(bookingId);
  }

  @override
  Future<ChatCredentials> chatToken(int bookingId) {
    return (onChatToken ??
        (id) async => ChatCredentials(bookingId: id, token: 'tok', baseUrl: 'https://goride.website/wp-json/goride/v1'))(
      bookingId,
    );
  }
}

class FakeChatRepository implements ChatRepository {
  Future<List<ChatMessage>> Function(int afterId)? onFetch;
  Future<void> Function(String text)? onSend;

  final List<int> fetchAfterIds = <int>[];
  final List<String> sent = <String>[];

  @override
  Future<List<ChatMessage>> fetch(ChatCredentials credentials, {required int afterId}) {
    fetchAfterIds.add(afterId);
    return (onFetch ?? (_) async => <ChatMessage>[])(afterId);
  }

  @override
  Future<void> send(ChatCredentials credentials, String text) {
    sent.add(text);
    return (onSend ?? (_) async {})(text);
  }
}

class FakeAuthRepository implements AuthRepository {
  int loginCalls = 0;
  int registerCalls = 0;
  Map<String, Object?>? lastRegister;
  Future<Session> Function()? onLogin;

  /// Si se asigna, register() espera a que se complete (simula una petición en vuelo).
  Completer<void>? registerGate;

  static Session session() => Session(
        token: 'bearer-token',
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
        userId: 7,
        role: 'customer',
      );

  @override
  Future<Session> login({required String email, required String password}) {
    loginCalls++;
    return (onLogin ?? () async => session())();
  }

  @override
  Future<Session> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required bool termsAccepted,
  }) async {
    registerCalls++;
    await registerGate?.future;
    lastRegister = <String, Object?>{'first': firstName, 'terms': termsAccepted};
    return session();
  }
}

ApiException networkUnknown() =>
    const ApiException(code: ApiException.timeout, message: '', outcomeUnknown: true);

ApiException apiError(String code, {int status = 409, Map<String, dynamic>? data, String message = 'x'}) =>
    ApiException(code: code, message: message, statusCode: status, data: data);

/// Espera a que se vacíen las tareas pendientes (microtareas).
Future<void> settle() => Future<void>.delayed(Duration.zero);
