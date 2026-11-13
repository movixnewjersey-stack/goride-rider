# CLIENT-TRIP-V2-DESIGN.md (versión regenerada 2026-10-23)

Reemplaza al borrador anterior (que no llegó a tu carpeta). Está alineado con el código entregado en `goride-rider-api` y con los archivos **reales de producción** que enviaste (`goride-live.php` sha256 `fc01a10b…9e9a`, `goride-api` con `autoload.php`/`Routes`/`Middleware`).

## 1. Qué hace la web hoy (verificado en producción)
| Pieza | Evidencia | Consecuencia |
|---|---|---|
| Token del pasajero `_goride_client_token` | `goride_get_or_create_token()`; sin caducidad | Es la única credencial de `goride/v1` |
| Entrega del token | shortcode `goride_client_live`, línea 1307: si falta `token`, lo crea y redirige **a cualquiera** | Quien conozca/adivine un `booking_id` obtiene el token (ver, chatear, cancelar) |
| `GET /goride/v1/last-booking` | sin autenticación | Revela el último `booking_id` |
| `POST /goride/v1/cancel` | solo valida token; no mira estado | Permite "cancelar" un viaje finalizado |
| `GET /goride/v1/trip-data` | línea 634: `// ... tus consultas ...`, `$changed` nunca true | **Siempre devuelve `{ok:true,timeout:true}`**: la web no recibe estado ni ubicación por esta ruta |
| Datos del conductor al pasajero | no existen en la web | Es nuevo |
| Viaje activo | user meta `_goride_active_booking` vía `admin-ajax` + cookie | No usable desde app |
| Notificación al pasajero | solo mensajes de sistema en el chat y widget web | No hay FCM a pasajeros |

> Esto son hechos del código. Que las rutas estén expuestas en el servidor en este momento no se probó contra goride.website.

## 2. Decisiones de diseño
1. **Plugin independiente** `goride-rider-api` (namespace `goride-rider/v1`). No se edita goride-api, goride-live, goride-dispatch, el tracker ni la app de conductores. Desactivarlo revierte todo.
2. **Autenticación**: se reutiliza `AuthMiddleware::authenticate()` real (Bearer v2, solo lectura de la clase). Falla cerrado si goride-api no está activo.
3. **Propiedad** = meta `_goride_user_id` escrita por este plugin al crear la reserva, con el usuario del Bearer. No se acepta coincidencia por correo (reservas web sin ese meta no son de nadie para la app; así un tercero no puede reclamarlas escribiendo un correo en el formulario web).
4. **Token de chat solo al dueño** (`/chat-token`), mismo patrón que `ChatController::chatToken` del conductor. La app reutiliza `goride/v1/chat` para conservar el push FCM al conductor.
5. **Estado derivado, solo lectura** desde `_goride_live_status` y `_goride_offer_state` (§4). Nada se escribe.
6. **Ubicación del conductor** se lee de `wp_goride_locations` (la que ya escribe la app de conductores) y se devuelve con `age_seconds`. Sondeo corto de 5 s; sin long-poll (limita conexiones MySQL en HostGator).
7. **Cancelación** valida propiedad y estado y delega en la ruta existente `/goride/v1/cancel` por `rest_do_request` interno con el token de cliente que solo conoce el servidor.
8. **Cotización → reserva** con cotización firmada (HMAC, 10 min, ligada al usuario) + recálculo del precio con el motor de CHBS al reservar (`PRICE_CHANGED` si difiere) + clave de idempotencia + candados atómicos (`add_option`) por clave y por usuario + un solo viaje bloqueante por usuario.
9. **Zona**: CHBS aplica "Driving Zone" solo en el navegador. El plugin la aplica en el servidor leyendo la configuración del formulario (país geocodificado por el servidor, radio). No define zonas.
10. **Distancia/duración** reales con `CHBSGoogleMapAPI::computeRoutes()` (la llave de Google ya configurada en CHBS), con el mismo redondeo que `validateBookingFormData()`.

## 3. Flujo
```
App                          goride-rider/v1                      CHBS / dispatch
 | POST /quotes ----------------> valida puntos, zona, ruta (Google), precio CHBS
 |<-- quote_id firmado + precio --|
 | POST /bookings (quote_id, idem)-> candados, ¿activo?, verifica firma, recalcula precio
 |                                |-- sendBooking() ---------------> crea chbs_booking
 |                                |   (+ _goride_user_id, idem)       save_post => dispatch ofrece al conductor
 |<-- 201 trip(searching) --------|
 | GET /trips/{id} cada 5 s ----->| estado + conductor + ubicación (solo lectura)
 | GET /trips/{id}/chat-token --->| token solo al dueño
 | GET|POST goride/v1/chat ------>| (existente)
 | POST /trips/{id}/cancel ------>| dueño + estado -> /goride/v1/cancel (existente)
```

## 4. Máquina de estados
`searching → driver_assigned → driver_arrived → finished`; `searching → no_drivers`; cualquier estado cancelable → `cancelled`. No existe estado "en curso" distinto de `driver_arrived` en el backend actual (el conductor solo marca llegada y finalizar): la app no inventa uno.

## 5. Brechas conocidas (no resueltas aquí, por alcance)
- `trip-data` roto y entrega de token abierta en la web: parche **opcional** en `OPCIONAL_endurecimiento_web/token_solo_dueno.diff` (no incluido en la instalación; requiere tu decisión porque cambia el comportamiento de la web).
- El despacho no notifica al conductor cuando el pasajero cancela (no hay listener de `goride_trip_cancelled_by_user` en `goride-dispatch.php`); solo queda el mensaje de sistema en el chat. Fuera de alcance (no se toca conductores/despacho).
- Reglas de disponibilidad/horario de CHBS no se aplican (`sendBooking()` no las evalúa; solo el asistente web). Pedir viaje "ahora" no depende de ellas hoy.
- Push FCM al pasajero: no existe. Fase posterior, backend separado.
