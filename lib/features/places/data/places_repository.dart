import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../trip/domain/trip.dart';
import '../domain/place.dart';

abstract class PlacesRepository {
  Future<List<PlaceSuggestion>> search(String query, {double? lat, double? lng, required String session});
  Future<GeoPoint> details(String placeId, {required String session});
  Future<GeoPoint> reverse(double lat, double lng);
}

/// Las búsquedas pasan por el servidor: la llave de Google no vive en la app.
class ApiPlacesRepository implements PlacesRepository {
  ApiPlacesRepository(this._api);

  final ApiClient _api;

  static const String _p = '${AppConfig.riderPrefix}/places';

  @override
  Future<List<PlaceSuggestion>> search(String query, {double? lat, double? lng, required String session}) async {
    final d = await _api.get(
      '$_p/autocomplete',
      query: <String, dynamic>{
        'q': query,
        'session': session,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      },
    );
    return (d['predictions'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  GeoPoint _place(Map<String, dynamic> d) {
    final p = d['place'];
    if (p is! Map) {
      throw const ApiException(code: ApiException.badResponse, message: 'Dirección incompleta.');
    }
    return GeoPoint.fromJson(Map<String, dynamic>.from(p));
  }

  @override
  Future<GeoPoint> details(String placeId, {required String session}) async {
    return _place(await _api.get('$_p/details', query: <String, dynamic>{'place_id': placeId, 'session': session}));
  }

  @override
  Future<GeoPoint> reverse(double lat, double lng) async {
    return _place(await _api.get('$_p/reverse', query: <String, dynamic>{'lat': lat, 'lng': lng}));
  }
}
