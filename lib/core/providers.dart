import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/places/data/places_repository.dart';
import '../features/trip/data/trip_repository.dart';
import 'dart:ui' as ui;

import '../features/trip/application/trip_providers.dart';
import 'api/api_client.dart';
import 'location/location_service.dart';
import 'push/push_gateway.dart';
import 'push/push_service.dart';
import 'session/session_controller.dart';
import 'storage/session_storage.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) => SecureSessionStorage());

final sessionControllerProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.watch(sessionStorageProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    readToken: () => ref.read(sessionControllerProvider).session?.token,
    onUnauthorized: () => ref.read(sessionControllerProvider.notifier).expire(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) => ApiAuthRepository(ref.watch(apiClientProvider)));

final tripRepositoryProvider = Provider<TripRepository>((ref) => ApiTripRepository(ref.watch(apiClientProvider)));

final placesRepositoryProvider =
    Provider<PlacesRepository>((ref) => ApiPlacesRepository(ref.watch(apiClientProvider)));

final chatRepositoryProvider = Provider<ChatRepository>((ref) => HttpChatRepository());

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());

final pushGatewayProvider = Provider<PushGateway>((ref) => FirebasePushGateway());

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(
    gateway: ref.watch(pushGatewayProvider),
    api: ref.watch(apiClientProvider),
    language: () => ui.PlatformDispatcher.instance.locale.languageCode,
    // Con la app abierta, un aviso del servidor adelanta la consulta del viaje.
    onForegroundMessage: () => ref.read(activeTripControllerProvider.notifier).recover(),
  );
  ref.onDispose(() => service.stop());
  return service;
});
