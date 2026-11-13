import 'package:equatable/equatable.dart';

double? _num(dynamic v) {
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse('$v');
}

int? _int(dynamic v) {
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse('$v');
}

/// Punto del mapa con su dirección legible.
class GeoPoint extends Equatable {
  const GeoPoint({
    required this.lat,
    required this.lng,
    required this.address,
    this.zipCode,
    this.countryCode,
  });

  factory GeoPoint.fromJson(Map<String, dynamic> j) => GeoPoint(
        lat: _num(j['lat']) ?? 0,
        lng: _num(j['lng']) ?? 0,
        address: '${j['address'] ?? ''}',
        zipCode: j['zip_code'] is String && (j['zip_code'] as String).isNotEmpty ? j['zip_code'] as String : null,
        countryCode:
            j['country_code'] is String && (j['country_code'] as String).isNotEmpty ? j['country_code'] as String : null,
      );

  final double lat;
  final double lng;
  final String address;
  final String? zipCode;
  final String? countryCode;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'address': address,
        if (zipCode != null) 'zip_code': zipCode,
        if (countryCode != null) 'country_code': countryCode,
      };

  @override
  List<Object?> get props => [lat, lng, address, zipCode, countryCode];
}

enum TripStatus {
  searching,
  noDrivers,
  driverAssigned,
  driverArrived,
  finished,
  cancelled,
  unknown;

  static TripStatus parse(String? raw) {
    switch (raw) {
      case 'searching':
        return TripStatus.searching;
      case 'no_drivers':
        return TripStatus.noDrivers;
      case 'driver_assigned':
        return TripStatus.driverAssigned;
      case 'driver_arrived':
        return TripStatus.driverArrived;
      case 'finished':
        return TripStatus.finished;
      case 'cancelled':
        return TripStatus.cancelled;
      default:
        return TripStatus.unknown;
    }
  }

  /// El viaje sigue en marcha (se sondea y bloquea pedir otro).
  bool get isLive => this == searching || this == driverAssigned || this == driverArrived;

  bool get hasDriver => this == driverAssigned || this == driverArrived;
}

class TripDriver extends Equatable {
  const TripDriver({required this.id, required this.firstName, this.photoUrl});

  factory TripDriver.fromJson(Map<String, dynamic> j) => TripDriver(
        id: _int(j['id']) ?? 0,
        firstName: '${j['first_name'] ?? ''}',
        photoUrl: j['photo_url'] is String && (j['photo_url'] as String).isNotEmpty ? j['photo_url'] as String : null,
      );

  final int id;
  final String firstName;
  final String? photoUrl;

  @override
  List<Object?> get props => [id, firstName, photoUrl];
}

class DriverLocation extends Equatable {
  const DriverLocation({required this.lat, required this.lng, this.ageSeconds});

  factory DriverLocation.fromJson(Map<String, dynamic> j) => DriverLocation(
        lat: _num(j['lat']) ?? 0,
        lng: _num(j['lng']) ?? 0,
        ageSeconds: _int(j['age_seconds']),
      );

  final double lat;
  final double lng;
  final int? ageSeconds;

  @override
  List<Object?> get props => [lat, lng, ageSeconds];
}

class Trip extends Equatable {
  const Trip({
    required this.bookingId,
    required this.status,
    required this.pickup,
    required this.dropoff,
    this.priceTotal,
    this.currency = 'USD',
    this.vehicleName,
    this.driver,
    this.driverLocation,
    this.canCancel = false,
    this.isTerminal = false,
  });

  factory Trip.fromJson(Map<String, dynamic> j) {
    final price = j['price'];
    return Trip(
      bookingId: _int(j['booking_id']) ?? 0,
      status: TripStatus.parse(j['status'] as String?),
      pickup: GeoPoint.fromJson(Map<String, dynamic>.from((j['pickup'] as Map?) ?? const {})),
      dropoff: GeoPoint.fromJson(Map<String, dynamic>.from((j['dropoff'] as Map?) ?? const {})),
      priceTotal: price is Map ? _num(price['total']) : null,
      currency: price is Map && price['currency'] is String ? price['currency'] as String : 'USD',
      vehicleName: j['vehicle_name'] as String?,
      driver: j['driver'] is Map ? TripDriver.fromJson(Map<String, dynamic>.from(j['driver'] as Map)) : null,
      driverLocation: j['driver_location'] is Map
          ? DriverLocation.fromJson(Map<String, dynamic>.from(j['driver_location'] as Map))
          : null,
      canCancel: j['can_cancel'] == true,
      isTerminal: j['is_terminal'] == true,
    );
  }

  final int bookingId;
  final TripStatus status;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final double? priceTotal;
  final String currency;
  final String? vehicleName;
  final TripDriver? driver;
  final DriverLocation? driverLocation;
  final bool canCancel;
  final bool isTerminal;

  bool get isLive => status.isLive;

  bool get locationIsStale =>
      driverLocation != null && (driverLocation!.ageSeconds ?? 0) > _staleSeconds;

  static const int _staleSeconds = 60;

  @override
  List<Object?> get props => [
        bookingId,
        status,
        pickup,
        dropoff,
        priceTotal,
        currency,
        vehicleName,
        driver,
        driverLocation,
        canCancel,
        isTerminal,
      ];
}

class Quote extends Equatable {
  const Quote({
    required this.quoteId,
    required this.expiresAt,
    required this.priceTotal,
    required this.currency,
    required this.priceFormatted,
    required this.distanceKm,
    required this.durationMin,
    required this.passengers,
    this.vehicleName,
  });

  factory Quote.fromJson(Map<String, dynamic> j) {
    final price = Map<String, dynamic>.from((j['price'] as Map?) ?? const {});
    return Quote(
      quoteId: '${j['quote_id']}',
      expiresAt: DateTime.tryParse('${j['expires_at']}') ?? DateTime.now(),
      priceTotal: _num(price['total']) ?? 0,
      currency: '${price['currency'] ?? 'USD'}',
      priceFormatted: '${price['formatted'] ?? ''}',
      distanceKm: _num(j['distance_km']) ?? 0,
      durationMin: _num(j['duration_min']) ?? 0,
      passengers: _int(j['passengers']) ?? 1,
      vehicleName: j['vehicle_name'] as String?,
    );
  }

  final String quoteId;
  final DateTime expiresAt;
  final double priceTotal;
  final String currency;
  final String priceFormatted;
  final double distanceKm;
  final double durationMin;
  final int passengers;
  final String? vehicleName;

  bool isExpired([DateTime? now]) => !expiresAt.isAfter(now ?? DateTime.now());

  @override
  List<Object?> get props => [quoteId, expiresAt, priceTotal, currency, distanceKm, durationMin, passengers];
}

class ServiceConfig extends Equatable {
  const ServiceConfig({required this.ready, required this.maxPassengers, this.blockingReasons = const []});

  factory ServiceConfig.fromJson(Map<String, dynamic> j) => ServiceConfig(
        ready: j['ready'] == true,
        maxPassengers: _int(j['max_passengers']) ?? 4,
        blockingReasons: (j['blocking_reasons'] as List? ?? const []).map((e) => '$e').toList(),
      );

  final bool ready;
  final int maxPassengers;
  final List<String> blockingReasons;

  @override
  List<Object?> get props => [ready, maxPassengers, blockingReasons];
}

class BookingResult {
  const BookingResult({required this.trip, required this.replayed});

  final Trip trip;
  final bool replayed;
}

class CancelResult {
  const CancelResult({required this.trip, required this.alreadyCancelled});

  final Trip trip;
  final bool alreadyCancelled;
}

class ChatCredentials extends Equatable {
  const ChatCredentials({required this.bookingId, required this.token, required this.baseUrl});

  factory ChatCredentials.fromJson(Map<String, dynamic> j) => ChatCredentials(
        bookingId: _int(j['booking_id']) ?? 0,
        token: '${j['token']}',
        baseUrl: '${j['chat_base_url']}',
      );

  final int bookingId;
  final String token;
  final String baseUrl;

  @override
  List<Object?> get props => [bookingId, token, baseUrl];
}
