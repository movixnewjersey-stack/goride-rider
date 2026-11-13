import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/api/api_exception.dart';
import 'package:goride_rider_app/features/chat/application/chat_controller.dart';
import 'package:goride_rider_app/features/chat/domain/chat_message.dart';

import '../../helpers/fakes.dart';

ChatMessage m(int id, String sender, String text) => ChatMessage(id: id, sender: sender, message: text);

void main() {
  late FakeTripRepository trips;
  late FakeChatRepository chat;
  late ChatController c;

  setUp(() {
    trips = FakeTripRepository();
    chat = FakeChatRepository();
    c = ChatController(bookingId: 100, trips: trips, chat: chat, autoPoll: false);
  });

  tearDown(() => c.dispose());

  List<ChatEntry> entries() => c.snapshot.entries;

  test('lee con after_id y avanza el cursor', () async {
    chat.onFetch = (after) async => after == 0 ? [m(1, 'driver', 'hola'), m(2, 'client', 'ok')] : [];
    await c.poll();
    await c.poll();
    expect(chat.fetchAfterIds, [0, 2]);
    expect(entries().map((e) => e.id), [1, 2]);
    expect(c.snapshot.ready, true);
  });

  test('NO DUPLICA: el mismo id repetido por el servidor se muestra una vez', () async {
    chat.onFetch = (_) async => [m(1, 'driver', 'hola')];
    await c.poll();
    await c.poll();
    await c.poll();
    expect(entries().length, 1);
  });

  test('ordena por id aunque lleguen desordenados', () async {
    chat.onFetch = (_) async => [m(3, 'driver', 'c'), m(1, 'driver', 'a'), m(2, 'client', 'b')];
    await c.poll();
    expect(entries().map((e) => e.text), ['a', 'b', 'c']);
  });

  test('el eco del servidor reemplaza el mensaje local (sin duplicar)', () async {
    chat.onFetch = (after) async => chat.sent.isEmpty ? [] : (after < 5 ? [m(5, 'client', 'ya voy')] : []);
    await c.poll();
    await c.send('  ya voy  ');
    expect(chat.sent, ['ya voy']);
    expect(entries().length, 1);
    expect(entries().single.delivery, ChatDelivery.sent);
    expect(entries().single.id, 5);
  });

  test('resultado DESCONOCIDO: no se reintenta solo; el usuario decide', () async {
    chat.onSend = (_) async => throw networkUnknown();
    await c.poll();
    await c.send('hola');
    await c.poll();
    await c.poll();
    expect(chat.sent.length, 1, reason: 'sin reintento automático');
    expect(entries().single.delivery, ChatDelivery.unknown);

    chat.onSend = (_) async {};
    await c.resend(entries().single.key);
    expect(chat.sent.length, 2);
    expect(entries().single.delivery, ChatDelivery.awaitingEcho);
  });

  test('si el mensaje sí había llegado, el sondeo lo reconcilia y desaparece el aviso', () async {
    var llego = false;
    chat.onFetch = (_) async => llego ? [m(7, 'client', 'hola')] : [];
    chat.onSend = (_) async {
      llego = true; // el servidor lo guardó pero la respuesta se perdió
      throw networkUnknown();
    };
    await c.poll();
    await c.send('hola');
    await settle();
    await c.poll();
    expect(entries().length, 1);
    expect(entries().single.delivery, ChatDelivery.sent);
  });

  test('fallo definitivo: queda marcado y se puede reintentar o descartar', () async {
    chat.onSend = (_) async => throw apiError('CHAT_ERROR', status: 500);
    await c.send('hola');
    expect(entries().single.delivery, ChatDelivery.failed);
    c.discard(entries().single.key);
    expect(entries(), isEmpty);
  });

  test('RECONEXIÓN: un fallo marca sin conexión y el siguiente éxito lo limpia', () async {
    var falla = true;
    chat.onFetch = (_) async {
      if (falla) {
        throw const ApiException(code: ApiException.networkError, message: '');
      }
      return [m(1, 'driver', 'aquí estoy')];
    };
    await c.poll();
    expect(c.snapshot.connectionLost, true);
    falla = false;
    await c.poll();
    expect(c.snapshot.connectionLost, false);
    expect(entries().single.text, 'aquí estoy');
  });

  test('sin token de chat: muestra el error y permite reintentar', () async {
    trips.onChatToken = (_) async => throw apiError('CHAT_TOKEN_UNAVAILABLE', status: 503, message: 'Chat no disponible');
    await c.poll();
    expect(c.snapshot.ready, false);
    expect(c.snapshot.error, 'Chat no disponible');
    trips.onChatToken = null;
    await c.poll();
    expect(c.snapshot.ready, true);
    expect(c.snapshot.error, isNull);
  });

  test('ignora mensajes vacíos o demasiado largos', () async {
    await c.send('   ');
    await c.send('x' * (ChatController.maxLength + 1));
    expect(chat.sent, isEmpty);
  });

  test('si hay 50 mensajes nuevos sigue leyendo hasta vaciar', () async {
    chat.onFetch = (after) async {
      if (after == 0) {
        return List.generate(50, (i) => m(i + 1, 'driver', 'm${i + 1}'));
      }
      return after == 50 ? [m(51, 'driver', 'último')] : [];
    };
    await c.poll();
    expect(entries().length, 51);
    expect(chat.fetchAfterIds, [0, 50]);
  });
}
