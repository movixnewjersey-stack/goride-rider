import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_exception.dart';
import 'package:goride_rider_app/core/providers.dart';
import 'package:goride_rider_app/core/storage/session_storage.dart';
import 'package:goride_rider_app/features/auth/presentation/login_screen.dart';
import 'package:goride_rider_app/features/auth/presentation/register_screen.dart';

import '../../helpers/fakes.dart';

Widget host(Widget child, FakeAuthRepository auth) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Login', () {
    testWidgets('no llama al servidor con campos vacíos', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(host(const LoginScreen(), auth));
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(auth.loginCalls, 0);
      expect(find.text('Escribe un correo válido'), findsOneWidget);
    });

    testWidgets('muestra el mensaje del servidor si las credenciales fallan', (tester) async {
      final auth = FakeAuthRepository()
        ..onLogin = () async => throw apiError('AUTH_INVALID_CREDENTIALS', status: 401, message: 'Correo o contraseña incorrectos');
      await tester.pumpWidget(host(const LoginScreen(), auth));
      await tester.enterText(find.byType(TextFormField).at(0), 'ana@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'secreto123');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      await tester.pump();
      expect(auth.loginCalls, 1);
      expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    });

    testWidgets('error de red: mensaje en español, sin texto técnico', (tester) async {
      final auth = FakeAuthRepository()
        ..onLogin = () async => throw const ApiException(code: ApiException.networkError, message: '');
      await tester.pumpWidget(host(const LoginScreen(), auth));
      await tester.enterText(find.byType(TextFormField).at(0), 'ana@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'secreto123');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });
  });

  group('Registro', () {
    Future<void> fill(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Ana');
      await tester.enterText(fields.at(1), 'Pérez');
      await tester.enterText(fields.at(2), 'ana@example.com');
      await tester.enterText(fields.at(3), '+19735550100');
      await tester.enterText(fields.at(4), 'secreto123');
    }

    testWidgets('el consentimiento nace SIN marcar', (tester) async {
      await tester.pumpWidget(host(const RegisterScreen(), FakeAuthRepository()));
      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, false);
    });

    testWidgets('sin aceptar no se registra y se explica por qué', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(host(const RegisterScreen(), auth));
      await fill(tester);
      await tester.ensureVisible(find.byKey(const Key('register_submit')));
      await tester.tap(find.byKey(const Key('register_submit')));
      await tester.pump();
      expect(auth.registerCalls, 0);
      expect(find.byKey(const Key('terms_error')), findsOneWidget);
    });

    testWidgets('con la casilla marcada por el usuario sí se registra, y solo una vez', (tester) async {
      final auth = FakeAuthRepository()..registerGate = Completer<void>();
      await tester.pumpWidget(host(const RegisterScreen(), auth));
      await fill(tester);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('register_submit')));
      await tester.tap(find.byKey(const Key('register_submit')));
      await tester.tap(find.byKey(const Key('register_submit'))); // doble toque
      await tester.pump();
      expect(auth.registerCalls, 1, reason: 'el segundo toque con la primera petición en vuelo no debe enviar otra');
      auth.registerGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(auth.registerCalls, 1);
      expect(auth.lastRegister!['terms'], true);
    });
  });
}
