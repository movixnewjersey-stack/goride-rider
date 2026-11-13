import 'package:geolocator/geolocator.dart';

enum LocationOutcome { granted, denied, deniedForever, serviceDisabled, unavailable }

class LocationResult {
  const LocationResult(this.outcome, {this.lat, this.lng});

  final LocationOutcome outcome;
  final double? lat;
  final double? lng;

  bool get hasPosition => outcome == LocationOutcome.granted && lat != null && lng != null;
}

/// La ubicación es opcional: negarla nunca bloquea la app (se escribe la dirección).
abstract class LocationService {
  Future<LocationResult> current({bool requestPermission = true});
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> current({bool requestPermission = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        return const LocationResult(LocationOutcome.denied);
      }
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      return LocationResult(LocationOutcome.granted, lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return const LocationResult(LocationOutcome.unavailable);
    }
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
