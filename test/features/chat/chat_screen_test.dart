import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/features/chat/application/chat_controller.dart';
import 'package:goride_rider_app/features/chat/application/chat_providers.dart';
import 'package:goride_rider_app/features/chat/domain/chat_message.dart';
import 'package:goride_rider_app/features/chat/presentation/chat_screen.dart';

import '../../helpers/fakes.dart';

Widget host(FakeTripRepository trips, FakeChatRepository chat) {
  return ProviderScope(
    overrides: [
      chatControllerProvider.overrideWith(
        (ref, bookingId) => ChatController(bookingId: bookingId, trips: trips, chat: chat, autoPoll: false),
      ),
    ],
    child: const MaterialApp(home: ChatScreen(bookingId: 100)),
  );
}

void main() {
  testWidgets('muestra los mensajes del servidor', (tester) async {
    final chat = FakeChatRepository()
      ..onFetch = (_) async => [
            const ChatMessage(id: 1, sender: 'driver', message: 'Ya llegué'),
            const ChatMessage(id: 2, sender: 'client', message: 'Bajo en un minuto'),
          ];
    await tester.pumpWidget(host(FakeTripRepository(), chat));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ya llegué'), findsOneWidget);
    expect(find.text('Bajo en un minuto'), findsOneWidget);
  });

  testWidgets('DOBLE TOQUE en enviar no duplica el mensaje', (tester) async {
    final chat = FakeChatRepository();
    await tester.pumpWidget(host(FakeTripRepository(), chat));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('chat_input')), 'Hola');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.pump();
    expect(chat.sent, ['Hola']);
  });

  testWidgets('resultado desconocido: avisa y ofrece reenviar sin hacerlo solo', (tester) async {
    final chat = FakeChatRepository()..onSend = (_) async => throw networkUnknown();
    await tester.pumpWidget(host(FakeTripRepository(), chat));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('chat_input')), 'Hola');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    await tester.pump();
    expect(find.text('No sabemos si se envió'), findsOneWidget);
    expect(find.text('Reenviar de todos modos'), findsOneWidget);
    expect(chat.sent.length, 1);
  });
}
