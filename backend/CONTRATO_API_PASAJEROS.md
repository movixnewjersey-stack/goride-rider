# GoRide Rider — Contrato definitivo de la API de pasajeros (v1)

Plugin: `goride-rider-api` 1.0.0 · Namespace REST: `/wp-json/goride-rider/v1`
Estado: **código y pruebas aisladas listos; NO instalado ni ejecutado en producción.**

## 0. Principios
- Autenticación: `Authorization: Bearer <access_token>` del login existente `POST /wp-json/goride/v2/auth/login` (sin cambios). Todas las rutas exigen Bearer.
- La app **nunca** recibe ni envía `booking_id` como credencial. La propiedad se valida en el servidor: `_goride_user_id` de la reserva == usuario del Bearer. Otro usuario recibe `404 TRIP_NOT_FOUND` (no se revela si existe).
- Precio, distancia, duración y país los calcula el servidor con el motor de CHBS. Lo que el cliente envíe en esos campos se ignora.
- Pago: solo efectivo (`payment_id=1` de CHBS). Si el formulario real no lo permite, la API responde `PAYMENT_NOT_COMPATIBLE`; **no cambia configuración**.
- Solo viajes inmediatos (el despacho actual arranca al guardar la reserva). `pickup_at` se rechaza.
- Sobre de respuesta (igual que goride-api): `{ "success": bool, "code": string|null, "message": string, "data": object|null }`. Todas las respuestas llevan `Cache-Control: no-store`.

## 1. Endpoints
| Método | Ruta | Para qué |
|---|---|---|
| GET | `/config` | ¿Está listo el servicio? motivos de bloqueo |
| POST | `/quotes` | Cotizar (solo lectura; no crea nada) |
| POST | `/bookings` | Crear la solicitud (idempotente) |
| GET | `/places/autocomplete?q=&lat=&lng=&session=` | Sugerencias de direcciones (Google vía servidor) |
| GET | `/places/details?place_id=&session=` | Coordenadas, dirección, zip y país de una sugerencia |
| GET | `/places/reverse?lat=&lng=` | Dirección de un punto (ubicación actual) |
| GET | `/trips/active` | Recuperar viaje activo al reabrir la app |
| GET | `/trips/{id}` | Estado, conductor y ubicación (sondeo corto) |
| GET | `/trips/{id}/driver` | Solo conductor + ubicación |
| GET | `/trips/{id}/chat-token` | Token de chat para el dueño |
| POST | `/trips/{id}/cancel` | Cancelar con validación de estados |

### 1.1 GET /config
`data`: `{ service:"distance", payment_methods:["cash"], max_passengers:4, ready:bool, blocking_reasons:["payment_not_compatible"|"vehicle_unresolved"|"fixed_locations"|"booking_form_missing"], scheduled_trips:false }`
La app deshabilita "Pedir viaje" si `ready=false` y muestra «Servicio no disponible por ahora».

### 1.2 POST /quotes
Request: `{ "pickup":{"lat":40.7357,"lng":-74.1724,"address":"…","zip_code"?,"country_code"?}, "dropoff":{…}, "passengers":1 }`
Response 200 `data`:
```json
{ "quote_id":"<token firmado>", "expires_at":"2026-10-23T15:10:00+00:00",
  "price":{"total":18.45,"currency":"USD","formatted":"$18.45"},
  "distance_km":12.3, "duration_min":25, "passengers":1, "vehicle_name":"Automóvil",
  "payment_method":"cash", "pickup":{…}, "dropoff":{…} }
```
La cotización vale 10 min y está firmada (HMAC) para ese usuario. Errores: `VALIDATION_ERROR 422`, `SAME_LOCATION 422`, `ZONE_NOT_ALLOWED 422`, `ZONE_UNVERIFIABLE 503`, `ROUTE_UNAVAILABLE 503`, `QUOTE_UNAVAILABLE 503`, `PAYMENT_NOT_COMPATIBLE 409`, `RATE_LIMITED 429` (20 por 10 min).

### 1.3 POST /bookings
Request: `{ "quote_id":"…", "idempotency_key":"<UUID/8-64 [A-Za-z0-9_-]>", "comment"?:"≤200" }` (la clave también puede ir en la cabecera `Idempotency-Key`).
- `201` primera creación: `data:{ trip:{…}, replayed:false }`
- `200` mismo `idempotency_key` repetido (doble toque, reintento tras perder conexión): **la misma reserva**, `replayed:true`. Nunca crea dos.
- `409 ACTIVE_TRIP_EXISTS` (con `data.trip`), `409 PRICE_CHANGED` (con `data.price` nuevo; la app muestra el nuevo precio y exige reconfirmar), `409 QUOTE_EXPIRED`, `409 REQUEST_IN_PROGRESS` (otra solicitud simultánea), `422 QUOTE_INVALID`, `422 VALIDATION_ERROR` (p. ej. perfil sin teléfono), `502 BOOKING_CREATION_FAILED` (CHBS no creó la reserva: **la app no debe mostrar éxito**).
- Generar la `idempotency_key` UNA vez por intento de usuario y reutilizarla en los reintentos de ese intento.

### 1.4 Objeto `trip`
```json
{ "booking_id":24310,
  "status":"searching|no_drivers|driver_assigned|driver_arrived|finished|cancelled",
  "status_raw":{"live":"","offer":"running"}, "status_at":null,
  "pickup":{"lat":…,"lng":…,"address":"…"}, "dropoff":{…},
  "price":{"total":18.45,"currency":"USD"} | null, "payment_method":"cash",
  "vehicle_name":"Automóvil" | null,
  "driver":{"id":12,"first_name":"Carlos","photo_url":"https://…"} | null,
  "driver_location":{"lat":…,"lng":…,"accuracy_m":8,"updated_at":"2026-10-23T14:10:03+00:00","age_seconds":12} | null,
  "can_cancel":true, "is_terminal":false, "server_time":"2026-10-23T14:10:15+00:00" }
```
- `booking_id` es un identificador de pantalla/rutas; **no es credencial**.
- El conductor solo expone nombre de pila y foto (sin teléfono ni correo). CHBS no guarda placa: no se muestra.
- `driver_location` solo existe con conductor asignado/llegado. `age_seconds` permite mostrar «hace N s» y marcar ubicación desactualizada (> 60 s).

### 1.5 Estados (derivados de metas reales, solo lectura)
| `status` | Origen |
|---|---|
| `searching` | `_goride_live_status` vacío y oferta `running` (o transitoria) |
| `no_drivers` | oferta `no_drivers`/`dispatch_failed`, o búsqueda > 30 min sin respuesta |
| `driver_assigned` | `_goride_live_status = accepted` |
| `driver_arrived` | `arrived_at_pickup` |
| `finished` | `finished` |
| `cancelled` | `cancelled_by_user` |
Cancelable: `searching`, `no_drivers`, `driver_assigned`, `driver_arrived`. Bloquean nuevos pedidos: `searching`, `driver_assigned`, `driver_arrived`.
Sondeo recomendado: `GET /trips/{id}` cada 5 s en pantalla visible (10–15 s con app en segundo plano), con retroceso exponencial ante errores. Sin long-polling para no agotar conexiones MySQL del hosting.

### 1.5b Places (búsqueda de direcciones)
La llave de Google de CHBS se queda en el servidor; la app no lleva llave de Maps para buscar.
- `autocomplete` → `data:{predictions:[{place_id,primary,secondary}]}` (máx. 8, sesgado a los países de la zona del formulario). `q` de 3 a 100 caracteres.
- `details` / `reverse` → `data:{place:{place_id,lat,lng,address,zip_code,country_code}}`.
- Errores: `VALIDATION_ERROR` (422), `PLACES_UNAVAILABLE` (503), `RATE_LIMITED` (429).

### 1.6 GET /trips/active
`data:{ trip: <trip>|null }`. Devuelve el viaje más reciente del usuario en `searching/driver_assigned/driver_arrived`, o uno `no_drivers` de los últimos 15 min (para mostrar el resultado). La app lo llama al abrirse y al volver a primer plano.

### 1.7 GET /trips/{id}/chat-token
`data:{ booking_id, token, chat_base_url:"https://goride.website/wp-json/goride/v1" }` — solo al dueño. El chat usa las rutas **existentes** (preserva la notificación FCM al conductor):
- `GET {chat_base_url}/chat?booking_id=&token=&after_id=` → `{ok,data:[{id,sender,message,created_at}]}` (máx. 50)
- `POST {chat_base_url}/chat` JSON `{booking_id, token, sender:"client", message}` → `{ok:true}`
- `GET {chat_base_url}/chat/long-poll?...` no se usa en la app (sondeo corto de `/chat` con `after_id` cada 4–5 s).
`created_at` de los mensajes está en **UTC** (excepción: el aviso «sin conductores» del despacho se guarda en hora local del sitio). Ordenar siempre por `id`.
Limitación conocida del chat existente: el POST no devuelve el `id` del mensaje ni admite idempotencia. La app evita duplicados reconciliando por `after_id` (mensaje local «enviando» se reemplaza por el recibido con mismo texto del remitente `client`) y no reintenta automáticamente un POST cuyo resultado se desconoce: pregunta al usuario.

### 1.8 POST /trips/{id}/cancel
`200` `data:{ trip, already_cancelled }` · `404 TRIP_NOT_FOUND` (no es suyo / no existe) · `409 TRIP_NOT_CANCELABLE` (`finished`) · `502 CANCEL_FAILED`.
Es idempotente: cancelar un viaje ya cancelado devuelve `200 already_cancelled:true` sin repetir efectos. Internamente invoca la ruta existente `POST /goride/v1/cancel` (mismos efectos y hooks).

## 2. Catálogo de errores
`AUTH_TOKEN_MISSING|AUTH_INVALID_TOKEN|AUTH_TOKEN_EXPIRED|AUTH_TOKEN_REVOKED|AUTH_USER_NOT_FOUND` (401) · `AUTH_UNAVAILABLE` (503) · `VALIDATION_ERROR|SAME_LOCATION|ZONE_NOT_ALLOWED|QUOTE_INVALID|IDEMPOTENCY_REQUIRED` (422) · `QUOTE_EXPIRED|PRICE_CHANGED|PAYMENT_NOT_COMPATIBLE|REQUEST_IN_PROGRESS|ACTIVE_TRIP_EXISTS|TRIP_NOT_CANCELABLE` (409) · `TRIP_NOT_FOUND` (404) · `RATE_LIMITED` (429) · `ZONE_UNVERIFIABLE|ROUTE_UNAVAILABLE|QUOTE_UNAVAILABLE|PLACES_UNAVAILABLE|CHAT_TOKEN_UNAVAILABLE` (503) · `BOOKING_CREATION_FAILED|CANCEL_FAILED` (502) · `INTERNAL_ERROR` (500). Los mensajes `message` ya están en español.

## 3. Rutas existentes que la app SÍ usa
`POST /goride/v2/auth/register` (con `terms_accepted`, `terms_version`, `privacy_version`; sin cabecera `X-GoRide-App`) · `POST /goride/v2/auth/login` · `GET /goride/v2/me` · `GET|POST /goride/v1/chat` (con el token de `/chat-token`).
## 4. Rutas que la app NUNCA usa
Todas las `…/driver/…` de v2, `POST /goride/v1/{location,finish}`, `GET /goride/v1/{last-booking,validate-booking,trip-data}`, `admin-ajax chbs_go_to_step`.

## 5. Qué NO cambia
goride-live, goride-dispatch, goride-api, tracker, compuerta 4.1/4.1b, notificaciones de conductores, formulario CHBS web, tarifas, métodos de pago y zona: **intactos**. El plugin no crea tablas ni opciones permanentes; solo escribe metas propias en la reserva que crea (`_goride_user_id`, `_goride_rider_created_via`, `_goride_rider_idem`, `_goride_rider_quoted_gross`) y candados temporales (opciones `goride_rider_lk_*`/`goride_rider_uk_*`, se borran solos).
