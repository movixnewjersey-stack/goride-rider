import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../domain/trip.dart';

abstract class TripRepository {
  Future<ServiceConfig> config();
  Future<Quote> quote({required GeoPoint pickup, required GeoPoint dropoff, required int passengers});
  Future<BookingResult> book({required String quoteId, required String idempotencyKey});
  Future<Trip?> active();
  Future<Trip> trip(int bookingId);
  Future<CancelResult> cancel(int bookingId);
  Future<ChatCredentials> chatToken(int bookingId);
}

class ApiTripRepository implements TripRepository {
  ApiTripRepository(this._api);

  final ApiClient _api;

  static const String _p = AppConfig.riderPrefix;

  Trip _trip(Map<String, dynamic> d) {
    final t = d['trip'];
    if (t is! Map) {
      throw const ApiException(code: ApiException.badResponse, message: 'Respuesta de viaje incompleta.');
    }
    return Trip.fromJson(Map<String, dynamic>.from(t));
  }

  @override
  Future<ServiceConfig> config() async => ServiceConfig.fromJson(await _api.get('$_p/config'));

  @override
  Future<Quote> quote({required GeoPoint pickup, required GeoPoint dropoff, required int passengers}) async {
    final d = await _api.post(
      '$_p/quotes',
      body: <String, dynamic>{
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'passengers': passengers,
      },
    );
    if (d['quote_id'] == null) {
      throw const ApiException(code: ApiException.badResponse, message: 'Cotización incompleta.');
    }
    return Quote.fromJson(d);
  }

  @override
  Future<BookingResult> book({required String quoteId, required String idempotencyKey}) async {
    final d = await _api.post(
      '$_p/bookings',
      body: <String, dynamic>{'quote_id': quoteId, 'idempotency_key': idempotencyKey},
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
    );
    return BookingResult(trip: _trip(d), replayed: d['replayed'] == true);
  }

  @override
  Future<Trip?> active() async {
    final d = await _api.get('$_p/trips/active');
    return d['trip'] is Map ? Trip.fromJson(Map<String, dynamic>.from(d['trip'] as Map)) : null;
  }

  @override
  Future<Trip> trip(int bookingId) async => _trip(await _api.get('$_p/trips/$bookingId'));

  @override
  Future<CancelResult> cancel(int bookingId) async {
    final d = await _api.post('$_p/trips/$bookingId/cancel');
    return CancelResult(trip: _trip(d), alreadyCancelled: d['already_cancelled'] == true);
  }

  @override
  Future<ChatCredentials> chatToken(int bookingId) async {
    final d = await _api.get('$_p/trips/$bookingId/chat-token');
    if (d['token'] == null) {
      throw const ApiException(code: 'CHAT_TOKEN_UNAVAILABLE', message: 'El chat no está disponible por ahora.');
    }
    return ChatCredentials.fromJson(d);
  }
}
