import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/session/session.dart';
import 'package:goride_rider_app/core/session/session_controller.dart';
import 'package:goride_rider_app/core/storage/session_storage.dart';

Session session({Duration validFor = const Duration(hours: 1)}) =>
    Session(token: 'abc', expiresAt: DateTime.now().add(validFor), userId: 3);

void main() {
  test('restaura una sesión vigente', () async {
    final c = SessionController(MemorySessionStorage(session()));
    await c.restore();
    expect(c.snapshot.status, SessionStatus.authenticated);
    c.dispose();
  });

  test('descarta una sesión caducada y la borra', () async {
    final storage = MemorySessionStorage(session(validFor: const Duration(seconds: -5)));
    final c = SessionController(storage);
    await c.restore();
    expect(c.snapshot.status, SessionStatus.unauthenticated);
    expect(storage.value, isNull);
    c.dispose();
  });

  test('sin sesión guardada => no autenticado', () async {
    final c = SessionController(MemorySessionStorage());
    await c.restore();
    expect(c.snapshot.status, SessionStatus.unauthenticated);
    c.dispose();
  });

  test('un 401 (expire) cierra la sesión local', () async {
    final storage = MemorySessionStorage();
    final c = SessionController(storage);
    await c.signIn(session());
    expect(c.snapshot.isAuthenticated, true);
    c.expire();
    await Future<void>.delayed(Duration.zero);
    expect(c.snapshot.status, SessionStatus.unauthenticated);
    expect(storage.value, isNull);
    c.dispose();
  });

  test('Session.fromAuthJson exige token y usuario', () {
    expect(() => Session.fromAuthJson(const <String, dynamic>{'user': <String, dynamic>{}}), throwsA(anything));
    final s = Session.fromAuthJson(const <String, dynamic>{
      'access_token': 'zzz',
      'expires_at': '2099-01-01T00:00:00+00:00',
      'user': <String, dynamic>{'id': 4, 'role': 'customer'},
    });
    expect(s.token, 'zzz');
    expect(s.userId, 4);
  });
}
