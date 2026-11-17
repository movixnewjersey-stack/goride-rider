import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Lee android/app/google-services.json. Si falta o falla, la app sigue
    // funcionando; solo quedan desactivados los avisos push.
    await Firebase.initializeApp();
  } catch (_) {}
  runApp(const ProviderScope(child: GoRideApp()));
}
