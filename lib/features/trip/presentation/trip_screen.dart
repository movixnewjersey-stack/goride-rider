import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../application/trip_providers.dart';
import '../domain/trip.dart';
import 'trip_format.dart';

class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key});

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  GoogleMapController? _map;
  String? _lastFit;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Set<Marker> _markers(Trip t) {
    return <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(t.pickup.lat, t.pickup.lng),
        infoWindow: const InfoWindow(title: 'Recogida'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(t.dropoff.lat, t.dropoff.lng),
        infoWindow: const InfoWindow(title: 'Destino'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (t.driverLocation != null && t.status.hasDriver)
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(t.driverLocation!.lat, t.driverLocation!.lng),
          infoWindow: InfoWindow(title: t.driver?.firstName ?? 'Conductor'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };
  }

  /// Encuadra recogida, destino y conductor. Nunca rompe si el mapa aún no está listo.
  Future<void> _fit(Trip t) async {
    final pts = <LatLng>[
      LatLng(t.pickup.lat, t.pickup.lng),
      LatLng(t.dropoff.lat, t.dropoff.lng),
      if (t.driverLocation != null && t.status.hasDriver) LatLng(t.driverLocation!.lat, t.driverLocation!.lng),
    ];
    final key = pts.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').join('|');
    if (key == _lastFit || _map == null) {
      return;
    }
    _lastFit = key;
    final south = pts.map((p) => p.latitude).reduce(math.min);
    final north = pts.map((p) => p.latitude).reduce(math.max);
    final west = pts.map((p) => p.longitude).reduce(math.min);
    final east = pts.map((p) => p.longitude).reduce(math.max);
    try {
      if (south == north && west == east) {
        await _map!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      } else {
        await _map!.animateCamera(
          CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)), 90),
        );
      }
    } catch (_) {
      // El mapa todavía no tiene tamaño; se reintentará en la próxima actualización.
      _lastFit = null;
    }
  }

  Future<void> _confirmCancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar el viaje?'),
        content: const Text('Si cancelas, tu solicitud se cerrará y tendrás que pedir otro viaje.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, seguir')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await ref.read(activeTripControllerProvider.notifier).cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeTripControllerProvider);
    final trip = active.trip;
    if (trip == null) {
      // El router te devuelve al inicio; mientras tanto, nada que mostrar.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fit(trip);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: LatLng(trip.pickup.lat, trip.pickup.lng), zoom: 13),
              onMapCreated: (c) {
                _map = c;
                _fit(trip);
              },
              markers: _markers(trip),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          if (active.connectionLost)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  key: const Key('connection_lost'),
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Sin conexión. Reintentando…'),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _TripCard(
              trip: trip,
              cancelling: active.cancelling,
              cancelError: active.cancelError,
              onCancel: _confirmCancel,
              onChat: () => context.push('/chat/${trip.bookingId}'),
              onClose: () => ref.read(activeTripControllerProvider.notifier).dismiss(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.cancelling,
    required this.cancelError,
    required this.onCancel,
    required this.onChat,
    required this.onClose,
  });

  final Trip trip;
  final bool cancelling;
  final String? cancelError;
  final VoidCallback onCancel;
  final VoidCallback onChat;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = trip.status;
    final done = s == TripStatus.finished || s == TripStatus.cancelled || s == TripStatus.noDrivers;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(statusTitle(s), key: const Key('trip_status'), style: theme.textTheme.titleLarge),
              if (s == TripStatus.searching)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (s == TripStatus.noDrivers)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Ningún conductor aceptó tu solicitud. Puedes intentarlo de nuevo en unos minutos.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (trip.driver != null && s.hasDriver) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: trip.driver!.photoUrl != null ? NetworkImage(trip.driver!.photoUrl!) : null,
                      child: trip.driver!.photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(trip.driver!.firstName, style: theme.textTheme.titleMedium),
                          if (trip.driverLocation != null)
                            Text(
                              trip.locationIsStale
                                  ? 'Ubicación desactualizada (hace ${trip.driverLocation!.ageSeconds ?? 0} s)'
                                  : 'Ubicación en vivo',
                              key: const Key('driver_location_note'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: trip.locationIsStale ? theme.colorScheme.error : null,
                              ),
                            )
                          else
                            Text('Esperando su ubicación…', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('chat_button'),
                      tooltip: 'Chat con tu conductor',
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ],
                ),
              ],
              const Divider(height: 24),
              _Line(icon: Icons.trip_origin, text: trip.pickup.address),
              const SizedBox(height: 6),
              _Line(icon: Icons.place, text: trip.dropoff.address),
              const SizedBox(height: 6),
              Text(
                'Total ${formatMoney(trip.priceTotal, trip.currency)} · Pago en efectivo',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (cancelError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(cancelError!, key: const Key('cancel_error'), style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 12),
              if (done)
                FilledButton(key: const Key('close_trip'), onPressed: onClose, child: const Text('Listo'))
              else if (trip.canCancel)
                OutlinedButton(
                  key: const Key('cancel_button'),
                  onPressed: cancelling ? null : onCancel,
                  child: cancelling
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Cancelar viaje'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
