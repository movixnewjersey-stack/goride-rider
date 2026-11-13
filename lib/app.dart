import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/session/session_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/trip/application/trip_providers.dart';
import 'routes/app_router.dart';

class GoRideApp extends ConsumerStatefulWidget {
  const GoRideApp({super.key});

  @override
  ConsumerState<GoRideApp> createState() => _GoRideAppState();
}

class _GoRideAppState extends ConsumerState<GoRideApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // restore() cede el control antes de cambiar el estado (no modifica nada durante el build).
    ref.read(sessionControllerProvider.notifier).restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(sessionControllerProvider);
    if (!session.isAuthenticated) {
      return;
    }
    final trips = ref.read(activeTripControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      // Al volver a primer plano el servidor manda: se vuelve a consultar el viaje.
      trips.recover();
      trips.resumePolling();
    } else if (state == AppLifecycleState.paused) {
      trips.pausePolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      final trips = ref.read(activeTripControllerProvider.notifier);
      if (next.isAuthenticated && !(prev?.isAuthenticated ?? false)) {
        trips.recover();
      } else if (!next.isAuthenticated && (prev?.isAuthenticated ?? false)) {
        trips.clear();
        ref.read(requestControllerProvider.notifier).reset();
      }
    });

    return MaterialApp.router(
      title: 'GoRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
