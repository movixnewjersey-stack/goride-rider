import '../domain/trip.dart';

String formatMoney(double? total, String currency) {
  if (total == null) {
    return '—';
  }
  final symbol = currency == 'USD' ? r'$' : '$currency ';
  return '$symbol${total.toStringAsFixed(2)}';
}

String formatMiles(double km) => '${(km * 0.621371).toStringAsFixed(1)} mi';

String formatMinutes(double min) => '${min.round()} min';

String statusTitle(TripStatus s) {
  switch (s) {
    case TripStatus.searching:
      return 'Buscando conductor…';
    case TripStatus.noDrivers:
      return 'No hay conductores disponibles';
    case TripStatus.driverAssigned:
      return 'Tu conductor va en camino';
    case TripStatus.driverArrived:
      return 'Tu conductor llegó';
    case TripStatus.finished:
      return 'Viaje finalizado';
    case TripStatus.cancelled:
      return 'Viaje cancelado';
    case TripStatus.unknown:
      return 'Actualizando…';
  }
}
