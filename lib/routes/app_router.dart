import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/session/session_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/trip/application/active_trip_controller.dart';
import '../features/trip/application/trip_providers.dart';
import '../features/trip/presentation/home_screen.dart';
import '../features/trip/presentation/trip_screen.dart';

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (prev?.status != next.status) {
        notifyListeners();
      }
    });
    ref.listen<ActiveTripState>(activeTripControllerProvider, (prev, next) {
      final changed = prev?.initialized != next.initialized || (prev?.trip == null) != (next.trip == null);
      if (changed) {
        notifyListeners();
      }
    });
  }
}

/// Reglas de navegación (única fuente de verdad):
///  - sin sesión => login/registro;
///  - con sesión pero sin haber consultado el viaje activo => splash;
///  - con viaje en el servidor => pantalla de viaje (se recupera al reabrir);
///  - sin viaje => inicio.
String? decideRoute({
  required SessionStatus session,
  required bool tripChecked,
  required bool hasTrip,
  required String location,
}) {
  bool at(String p) => location == p || location.startsWith('$p/');

  switch (session) {
    case SessionStatus.unknown:
      return location == '/splash' ? null : '/splash';
    case SessionStatus.unauthenticated:
      return (location == '/login' || location == '/register') ? null : '/login';
    case SessionStatus.authenticated:
      if (!tripChecked) {
        return location == '/splash' ? null : '/splash';
      }
      if (hasTrip) {
        return (location == '/trip' || at('/chat')) ? null : '/trip';
      }
      return location == '/home' ? null : '/home';
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final active = ref.read(activeTripControllerProvider);
      return decideRoute(
        session: session.status,
        tripChecked: active.initialized,
        hasTrip: active.trip != null,
        location: state.matchedLocation,
      );
    },
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/trip', builder: (_, __) => const TripScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(bookingId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('GoRide', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
