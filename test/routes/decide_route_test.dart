import 'package:flutter_test/flutter_test.dart';
import 'package:goride_rider_app/core/session/session_controller.dart';
import 'package:goride_rider_app/routes/app_router.dart';

String? go(SessionStatus s, {bool checked = true, bool trip = false, String at = '/home'}) =>
    decideRoute(session: s, tripChecked: checked, hasTrip: trip, location: at);

void main() {
  test('sesión desconocida => splash', () {
    expect(go(SessionStatus.unknown, at: '/home'), '/splash');
    expect(go(SessionStatus.unknown, at: '/splash'), isNull);
  });

  test('sin sesión => solo login/registro', () {
    expect(go(SessionStatus.unauthenticated, at: '/home'), '/login');
    expect(go(SessionStatus.unauthenticated, at: '/trip'), '/login');
    expect(go(SessionStatus.unauthenticated, at: '/register'), isNull);
    expect(go(SessionStatus.unauthenticated, at: '/login'), isNull);
  });

  test('con sesión pero sin comprobar viaje activo => splash (no parpadea el inicio)', () {
    expect(go(SessionStatus.authenticated, checked: false, at: '/login'), '/splash');
    expect(go(SessionStatus.authenticated, checked: false, at: '/splash'), isNull);
  });

  test('RECUPERACIÓN: con viaje en curso, todo lleva a /trip (o al chat)', () {
    expect(go(SessionStatus.authenticated, trip: true, at: '/splash'), '/trip');
    expect(go(SessionStatus.authenticated, trip: true, at: '/home'), '/trip');
    expect(go(SessionStatus.authenticated, trip: true, at: '/trip'), isNull);
    expect(go(SessionStatus.authenticated, trip: true, at: '/chat/12'), isNull);
  });

  test('sin viaje => inicio; /trip y /chat ya no aplican', () {
    expect(go(SessionStatus.authenticated, at: '/splash'), '/home');
    expect(go(SessionStatus.authenticated, at: '/login'), '/home');
    expect(go(SessionStatus.authenticated, at: '/trip'), '/home');
    expect(go(SessionStatus.authenticated, at: '/chat/12'), '/home');
    expect(go(SessionStatus.authenticated, at: '/home'), isNull);
  });
}
