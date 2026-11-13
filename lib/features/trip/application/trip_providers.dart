import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'active_trip_controller.dart';
import 'request_controller.dart';

final requestControllerProvider = StateNotifierProvider<RequestController, RequestState>((ref) {
  return RequestController(ref.watch(tripRepositoryProvider));
});

final activeTripControllerProvider = StateNotifierProvider<ActiveTripController, ActiveTripState>((ref) {
  return ActiveTripController(ref.watch(tripRepositoryProvider));
});

final serviceConfigProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(tripRepositoryProvider).config();
});
