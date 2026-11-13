# GoRide (app de pasajeros, Android)

Proyecto Flutter **independiente** de la app de conductores.
Paquete Android `com.goride.rider` · nombre visible `GoRide` · iOS fuera de alcance.

> **Estado honesto.** Todo el código y las pruebas de este proyecto están **escritos pero NO ejecutados**: mi entorno no tiene Flutter/Dart. Lo primero que debes hacer es `flutter pub get`, `flutter analyze` y `flutter test` (pasos abajo) y enviarme la salida completa para corregir lo que salga. Nada se ha probado contra goride.website ni en un teléfono.

## 0. Requisito del servidor (sin esto la app no puede pedir viajes)

La app usa la API segura nueva `goride-rider/v1` del plugin **goride-rider-api** (paquete `goride_rider_backend`). Ese plugin **todavía no está instalado**. Hasta que lo instales, el login funciona (usa `goride/v2/auth/*`, que ya existe) pero cotizar, pedir, viaje activo y chat darán error.
Instálalo siguiendo `INSTALACION_Y_REVERSA.md` del paquete backend (respaldo, consultas de solo lectura, prueba de cotización, reversa).

## 1. Preparar el proyecto en tu PC

1. Descomprime este paquete de modo que `pubspec.yaml` quede en `C:\Users\User\Downloads\goride_rider_app\pubspec.yaml`.
2. Crea la carpeta `android` (una sola vez; usa tu Flutter y fija `com.goride.rider`):

```powershell
cd C:\Users\User\Downloads\goride_rider_app
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup_android.ps1 -MapsApiKey "PEGA_AQUI_TU_LLAVE_DE_MAPS"
```

   - Usa la misma configuración de Gradle/Java que ya compila en la app de conductores (Java 25, compileSdk 36). Si tu PC usa otra versión: `-JavaVersion 17`.
   - Si no pasas la llave, el mapa sale gris hasta que edites `android\app\src\main\AndroidManifest.xml`.
3. Dependencias, análisis y pruebas:

```powershell
flutter pub get
```

```powershell
flutter analyze
```

```powershell
flutter test
```

4. Ejecutar en el teléfono (con depuración USB activada en el Moto e15):

```powershell
flutter devices
```

```powershell
flutter run -d ID_DEL_DISPOSITIVO
```

5. APK de prueba instalable:

```powershell
flutter build apk --release
```

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Otro servidor para pruebas: `flutter run --dart-define=API_BASE=https://otro-sitio/wp-json`.

## 2. Llave de Google Maps

- Solo hace falta para **dibujar el mapa**. La búsqueda de direcciones pasa por el servidor (la llave de CHBS no sale de allí).
- En Google Cloud: habilita **Maps SDK for Android** y crea una llave **restringida** a Android, paquete `com.goride.rider` y la huella SHA-1 de tu llave de depuración:

```powershell
cd android
```

```powershell
.\gradlew signingReport
```

- No uses la llave de CHBS en la app.

## 3. Firebase (proyecto `goride-driver-41379`, app Android separada)

El MVP **no usa Firebase** (no hay push al pasajero en el servidor todavía), así que no hace falta para compilar. Déjalo preparado así:

1. Consola Firebase → proyecto `goride-driver-41379` → *Agregar app* → Android.
2. Nombre del paquete: `com.goride.rider` (NO el de conductores). Apodo: `GoRide Rider`.
3. Agrega la huella SHA-1 (comando de arriba).
4. Descarga **su propio** `google-services.json` y guárdalo en `android\app\google-services.json` (está en `.gitignore`).
5. No reemplaces ni toques el `google-services.json` de la app de conductores.
6. Cuando se haga la fase de notificaciones push (requiere cambio en el servidor: guardar el token FCM del pasajero y enviarlo desde el despacho), se agregan `firebase_core`/`firebase_messaging` y el plugin `com.google.gms.google-services`. No está hecho.

## 4. Endpoints que usa la app (contrato definitivo en `CONTRATO_API_PASAJEROS.md`)

| Uso | Método y ruta | Origen |
|---|---|---|
| Login | `POST /goride/v2/auth/login` | existente (goride-api) |
| Registro (+ `terms_accepted`, `terms_version`, `privacy_version`) | `POST /goride/v2/auth/register` | existente |
| ¿Servicio listo? | `GET /goride-rider/v1/config` | nuevo |
| Buscar dirección | `GET /goride-rider/v1/places/autocomplete`, `/details`, `/reverse` | nuevo |
| Cotizar | `POST /goride-rider/v1/quotes` | nuevo |
| Pedir (idempotente) | `POST /goride-rider/v1/bookings` (+ `Idempotency-Key`) | nuevo |
| Viaje activo al reabrir | `GET /goride-rider/v1/trips/active` | nuevo |
| Estado + conductor + ubicación (cada 5 s) | `GET /goride-rider/v1/trips/{id}` | nuevo |
| Cancelar | `POST /goride-rider/v1/trips/{id}/cancel` | nuevo (delega en `goride/v1/cancel`) |
| Token de chat (solo dueño) | `GET /goride-rider/v1/trips/{id}/chat-token` | nuevo |
| Leer / enviar chat | `GET`/`POST /goride/v1/chat` | existente (goride-live) |

Todo con `Authorization: Bearer`. Sobre estándar `{success, code, message, data}`. Los POST llevan siempre cuerpo JSON (Mod_Security).

## 5. Funciones de la web → pantalla nativa

| Web actual | App nativa | Archivo |
|---|---|---|
| Login / registro WooCommerce | Login y registro con casilla de términos **sin marcar** y visor legal integrado | `features/auth` |
| Formulario CHBS paso 1 (trayecto) | Inicio: mapa + recogida/destino + pasajeros | `trip/presentation/home_screen.dart` |
| Autocompletar de Google en CHBS | Búsqueda de dirección vía servidor | `places/` |
| Ubicación del navegador | Permiso con explicación y negación sin bloqueo (se escribe la dirección) | `core/location`, `home_screen.dart` |
| Pasos 2–4 (vehículo, datos, resumen) | Tarjeta de cotización (precio CHBS calculado por el servidor) + «Pedir viaje» | `request_controller.dart` |
| Paso 5 (`sendBooking`) | `POST /bookings` idempotente; nunca simula éxito | `request_controller.dart` |
| Pago | Solo efectivo (lo que el formulario permite) | servidor |
| Despacho / búsqueda de conductor | Estados `searching`, `no_drivers`, `driver_assigned`, `driver_arrived` del servidor | `trip_screen.dart` |
| Widget «viaje activo» (cookie) | Recuperación del viaje al abrir y al volver a primer plano | `active_trip_controller.dart` |
| `/ride-live` (seguimiento) | Pantalla de viaje: marcadores, conductor, ubicación con antigüedad | `trip_screen.dart` |
| Chat | Chat con sondeo corto, sin duplicados | `features/chat` |
| Cancelar | Cancelar con confirmación y validación en servidor | `active_trip_controller.dart` |
| Resumen final | Tarjeta de viaje finalizado/cancelado + «Listo» | `trip_screen.dart` |
| Viajes programados | **No incluido** (el servidor los rechaza) | — |
| Notificaciones | **No incluido** (no existe push al pasajero) | — |

## 6. Qué está verificado y qué no

| Qué | Simulador / pruebas aisladas | Servidor real | Teléfono real |
|---|---|---|---|
| Backend PHP (cotización, reserva, cancelación, activo, chat-token, places) | ✅ 130 pruebas, `php -l` | ❌ no instalado | — |
| `ChbsGatewayLive` contra CHBS real | ❌ | ❌ | — |
| Código Flutter compila / `flutter analyze` | ❌ **no ejecutado** | — | — |
| Pruebas Flutter (≈ 70 casos escritos) | ❌ **no ejecutadas** | — | — |
| Login / registro contra goride.website | ❌ | ❌ | ❌ |
| Cotizar y pedir | ❌ | ❌ | ❌ |
| Mapa, ubicación, permisos | ❌ | — | ❌ |
| Chat, cancelar, recuperar viaje | ❌ | ❌ | ❌ |

Las pruebas escritas cubren: errores del API (sobre, HTML, timeouts con resultado desconocido, 401), doble toque al pedir/cancelar/enviar chat, reintento con la misma clave, `PRICE_CHANGED`, recuperación del viaje activo, reconexión (viaje y chat), no duplicar mensajes, reglas del router y consentimiento sin marcar. **No** hay pruebas de widgets de `HomeScreen`/`TripScreen` (usan Google Maps, que requiere la plataforma nativa): se cubren con la lista manual.

## 7. Pruebas manuales en el Moto e15 (corta)

Antes: plugin `goride-rider-api` instalado y probado con la guía del backend; un conductor de prueba en línea.

1. Instala el APK, ábrelo: ¿llega a Login? Registra una cuenta de prueba **sin** marcar la casilla: debe impedirlo. Abre los dos enlaces legales. Marca y registra.
2. Cierra sesión e inicia con esa cuenta. Cierra la app del todo y ábrela: debe seguir con sesión.
3. Ubicación: acepta el diálogo → el mapa se centra y rellena la recogida. Repite negando el permiso: la app sigue usable escribiendo la dirección.
4. Busca una recogida y un destino en New Jersey: aparece el precio. Cambia pasajeros: el precio se recalcula.
5. Destino fuera de la zona: debe decir que no está disponible, sin crear nada.
6. Toca **Pedir viaje** rápido dos veces: en el panel de CHBS/WordPress debe existir **una sola** reserva.
7. Apaga datos justo al pedir: debe decir que no sabe si llegó y ofrecer «Reintentar»; al reintentar, **una sola** reserva.
8. Con el conductor de prueba: acepta → «Tu conductor va en camino», nombre/foto, punto en el mapa. Llega → «Tu conductor llegó».
9. Cierra la app con el viaje en curso y reábrela: debe volver directo a la pantalla de viaje.
10. Chat: envía un mensaje; debe aparecer una sola vez y el conductor debe recibirlo. Responde desde el conductor: llega en ≤ 5 s. Corta el wifi y vuélvelo a encender: se reanuda sin duplicar.
11. Cancelar: con otro viaje, cancela con confirmación; la reserva queda cancelada. Intenta cancelar uno ya finalizado: mensaje claro.
12. Finaliza un viaje desde el conductor: aparece el resumen y «Listo» vuelve al inicio.

## 8. Limitaciones conocidas (no ocultas)

- No se dibuja la línea de la ruta (no hay endpoint que entregue el trazado; se muestran marcadores). Se puede añadir al backend después.
- Sin push al pasajero: el estado se entera por sondeo cada 5 s mientras la app está abierta.
- El despacho existente no avisa al conductor cuando el pasajero cancela (limitación del servidor, documentada en el paquete backend).
- El POST del chat existente no devuelve id ni admite idempotencia: la app no reintenta sola y marca «No sabemos si se envió».
- Las reglas de disponibilidad de CHBS fuera del asistente web no se aplican (documentado en el backend).
- Distancias en millas por usarse tarifa por milla; el servidor entrega kilómetros.

## 9. Estructura

```
lib/
  core/        api (cliente, errores), config, session, storage, location, theme, util
  features/
    auth/      domain, data, presentation (login, registro, visor legal)
    places/    búsqueda de direcciones
    trip/      domain (modelos), data, application (cotizar/pedir, viaje activo), presentation
    chat/      domain, data, application, presentation
  routes/      go_router + reglas de redirección
test/          core, features, routes, helpers (fakes)
scripts/       setup_android.ps1
```
