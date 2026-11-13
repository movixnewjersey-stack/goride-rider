import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/providers.dart';
import '../../places/presentation/place_search_screen.dart';
import '../application/request_controller.dart';
import '../application/trip_providers.dart';
import '../domain/trip.dart';
import 'trip_format.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  GoogleMapController? _map;
  bool _locationAsked = false;
  bool _locating = false;
  bool _locationGranted = false;
  String? _locationNotice;
  double? _biasLat;
  double? _biasLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askLocationOnce());
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  Future<void> _askLocationOnce() async {
    if (_locationAsked || !mounted) {
      return;
    }
    _locationAsked = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar tu ubicación'),
        content: const Text(
          'GoRide usa tu ubicación para llenar el punto de recogida y mostrarte en el mapa. '
          'Solo se usa mientras la app está abierta. Si prefieres, puedes escribir la dirección.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (go == true) {
      await _locate();
    }
  }

  Future<void> _locate() async {
    if (_locating) {
      return;
    }
    setState(() {
      _locating = true;
      _locationNotice = null;
    });
    final result = await ref.read(locationServiceProvider).current();
    if (!mounted) {
      return;
    }
    switch (result.outcome) {
      case LocationOutcome.granted:
        _locationGranted = true;
        _biasLat = result.lat;
        _biasLng = result.lng;
        await _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(result.lat!, result.lng!), 15));
        try {
          final p = await ref.read(placesRepositoryProvider).reverse(result.lat!, result.lng!);
          if (mounted) {
            ref.read(requestControllerProvider.notifier).setPickup(p);
          }
        } catch (e) {
          if (mounted) {
            _locationNotice = 'No pudimos obtener la dirección de tu posición. ${userMessage(e)} Escríbela a mano.';
          }
        }
      case LocationOutcome.denied:
        _locationNotice = 'Sin permiso de ubicación. Escribe la dirección de recogida.';
      case LocationOutcome.deniedForever:
        _locationNotice = 'El permiso de ubicación está bloqueado. Puedes activarlo en Ajustes o escribir la dirección.';
      case LocationOutcome.serviceDisabled:
        _locationNotice = 'La ubicación del teléfono está apagada. Actívala o escribe la dirección.';
      case LocationOutcome.unavailable:
        _locationNotice = 'No pudimos obtener tu ubicación. Escribe la dirección de recogida.';
    }
    if (mounted) {
      setState(() => _locating = false);
    }
  }

  Future<void> _pickPlace({required bool pickup}) async {
    final point = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute<GeoPoint>(
        builder: (_) => PlaceSearchScreen(
          title: pickup ? 'Punto de recogida' : '¿A dónde vas?',
          biasLat: _biasLat,
          biasLng: _biasLng,
        ),
      ),
    );
    if (point == null || !mounted) {
      return;
    }
    final c = ref.read(requestControllerProvider.notifier);
    pickup ? c.setPickup(point) : c.setDropoff(point);
    unawaited(_map?.animateCamera(CameraUpdate.newLatLng(LatLng(point.lat, point.lng))));
  }

  Set<Marker> _markers(RequestState s) {
    return <Marker>{
      if (s.pickup != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(s.pickup!.lat, s.pickup!.lng),
          infoWindow: const InfoWindow(title: 'Recogida'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      if (s.dropoff != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(s.dropoff!.lat, s.dropoff!.lng),
          infoWindow: const InfoWindow(title: 'Destino'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };
  }

  Future<void> _signOut() async {
    ref.read(activeTripControllerProvider.notifier).clear();
    ref.read(requestControllerProvider.notifier).reset();
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(requestControllerProvider);
    final active = ref.watch(activeTripControllerProvider);
    final config = ref.watch(serviceConfigProvider);

    // Un viaje creado por el servidor pasa a ser el viaje activo; el router abre la pantalla de viaje.
    ref.listen<RequestState>(requestControllerProvider, (prev, next) {
      final trip = next.createdTrip;
      if (trip != null && prev?.createdTrip == null) {
        ref.read(activeTripControllerProvider.notifier).adopt(trip);
        ref.read(requestControllerProvider.notifier).reset();
      }
    });

    final start = LatLng(_biasLat ?? AppConfig.defaultLat, _biasLng ?? AppConfig.defaultLng);
    final maxPassengers = config.valueOrNull?.maxPassengers ?? 4;
    final serviceDown = config.valueOrNull != null && !config.valueOrNull!.ready;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: start, zoom: 13),
              onMapCreated: (c) => _map = c,
              markers: _markers(s),
              myLocationEnabled: _locationGranted,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: PopupMenuButton<String>(
                  tooltip: 'Menú',
                  icon: const CircleAvatar(child: Icon(Icons.menu)),
                  onSelected: (v) {
                    if (v == 'logout') {
                      _signOut();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(value: 'logout', child: Text('Cerrar sesión')),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Panel(
              state: s,
              maxPassengers: maxPassengers,
              serviceDown: serviceDown,
              recoverError: active.recoverError,
              locationNotice: _locationNotice,
              locating: _locating,
              onRetryRecover: () => ref.read(activeTripControllerProvider.notifier).recover(),
              onLocate: _locate,
              onOpenSettings: () => ref.read(locationServiceProvider).openAppSettings(),
              onPickPickup: () => _pickPlace(pickup: true),
              onPickDropoff: () => _pickPlace(pickup: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({
    required this.state,
    required this.maxPassengers,
    required this.serviceDown,
    required this.recoverError,
    required this.locationNotice,
    required this.locating,
    required this.onRetryRecover,
    required this.onLocate,
    required this.onOpenSettings,
    required this.onPickPickup,
    required this.onPickDropoff,
  });

  final RequestState state;
  final int maxPassengers;
  final bool serviceDown;
  final String? recoverError;
  final String? locationNotice;
  final bool locating;
  final VoidCallback onRetryRecover;
  final VoidCallback onLocate;
  final VoidCallback onOpenSettings;
  final VoidCallback onPickPickup;
  final VoidCallback onPickDropoff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(requestControllerProvider.notifier);
    final quote = state.quote;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (serviceDown)
                _Banner(
                  key: const Key('service_down'),
                  text: 'Servicio no disponible por ahora. Inténtalo más tarde.',
                  color: theme.colorScheme.errorContainer,
                ),
              if (recoverError != null)
                _Banner(
                  text: 'No pudimos comprobar si tienes un viaje en curso.',
                  color: theme.colorScheme.errorContainer,
                  action: TextButton(onPressed: onRetryRecover, child: const Text('Reintentar')),
                ),
              if (locationNotice != null)
                _Banner(
                  text: locationNotice!,
                  color: theme.colorScheme.secondaryContainer,
                  action: TextButton(onPressed: onOpenSettings, child: const Text('Ajustes')),
                ),
              _PlaceField(
                key: const Key('pickup_field'),
                icon: Icons.trip_origin,
                label: 'Recogida',
                value: state.pickup?.address,
                onTap: onPickPickup,
                trailing: IconButton(
                  tooltip: 'Usar mi ubicación',
                  onPressed: locating ? null : onLocate,
                  icon: locating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                ),
              ),
              const SizedBox(height: 8),
              _PlaceField(
                key: const Key('dropoff_field'),
                icon: Icons.place,
                label: '¿A dónde vas?',
                value: state.dropoff?.address,
                onTap: onPickDropoff,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.group_outlined),
                  const SizedBox(width: 8),
                  const Text('Pasajeros'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Menos pasajeros',
                    onPressed: state.passengers > 1 ? () => controller.setPassengers(state.passengers - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${state.passengers}', key: const Key('passengers_value')),
                  IconButton(
                    tooltip: 'Más pasajeros',
                    onPressed:
                        state.passengers < maxPassengers ? () => controller.setPassengers(state.passengers + 1) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (state.quoteStatus == QuoteStatus.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (state.quoteStatus == QuoteStatus.error)
                _Banner(
                  key: const Key('quote_error'),
                  text: state.quoteError ?? 'No pudimos cotizar.',
                  color: theme.colorScheme.errorContainer,
                  action: TextButton(onPressed: controller.requestQuote, child: const Text('Reintentar')),
                ),
              if (quote != null && state.quoteStatus == QuoteStatus.ready)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.priceFormatted.isNotEmpty ? quote.priceFormatted : formatMoney(quote.priceTotal, quote.currency),
                        key: const Key('quote_price'),
                        style: theme.textTheme.headlineMedium,
                      ),
                      Text(
                        '${formatMiles(quote.distanceKm)} · ${formatMinutes(quote.durationMin)} · Pago en efectivo',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (state.priceChangedTo != null)
                Text(
                  'Nuevo precio: ${formatMoney(state.priceChangedTo, quote?.currency ?? 'USD')}',
                  key: const Key('price_changed'),
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                ),
              if (state.bookingError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.bookingError!,
                    key: const Key('booking_error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (state.blockingTrip != null)
                OutlinedButton(
                  onPressed: () {
                    ref.read(activeTripControllerProvider.notifier).adopt(state.blockingTrip!);
                    controller.reset();
                  },
                  child: const Text('Ver mi viaje en curso'),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('request_button'),
                onPressed: (state.canRequest && !serviceDown) ? controller.confirm : null,
                child: state.bookingStatus == BookingStatus.submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(state.bookingOutcomeUnknown ? 'Reintentar' : 'Pedir viaje'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  value ?? label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: value == null
                      ? theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                      : theme.textTheme.bodyLarge,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.color, this.action});

  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
