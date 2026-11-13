# Verificación contra los archivos reales de producción (2026-10-23)

| Archivo recibido | sha256 | Resultado |
|---|---|---|
| `goride-live__2_.php` (2969 líneas) | `fc01a10bef86ed9228ca820955d9dd1e85170f7b6a5ec517c31b16186b179e9a` | **Difiere** de la copia anterior (2825 líneas, `56bfea2b…948536b`) |
| `goride-active-trip.js` | `e5f92541a5ea27b5ff582493d2e9758c430c047e0c7b35d8f6d3a0883ee56e97` | Idéntico a la copia anterior |
| `goride-api_1.zip` | (carpeta `goride-api/`, 84+ archivos) | Arquitectura real: `Routes/*::register()` + `Controllers` + `AuthMiddleware`; sin clase `Router` |

## Diferencias producción vs copia anterior (goride-live)
- Tabla `goride_driver_documents` (bloque 2.2), `goride_notify_client_status()`, `goride_finish_trip()` extraída de `/finish`, push FCM al conductor cuando el pasajero escribe en el chat, y `created_at` de mensajes en UTC (`current_time('mysql', true)`).
- **Sin diferencias** en: `trip-data`, `cancel`, `last-booking`, `validate-booking`, shortcode `goride_client_live`. En `chat` solo cambia el push FCM al conductor y la hora UTC.

## Hallazgos: CONFIRMADOS en el archivo de producción
| # | Hallazgo | Evidencia |
|---|---|---|
| 1 | Entrega del token a cualquiera | línea 1307 |
| 2 | `/cancel` sin validación de estado | líneas 856-901 |
| 3 | `/trip-data` es un esqueleto (siempre `timeout:true`) | línea 634 |
| 4 | `/last-booking` y `/validate-booking` sin autenticación | líneas 514-552 |

## NO verificado (requiere servidor o capturas)
- Que esas rutas respondan así hoy en goride.website (no hay red desde el entorno de desarrollo).
- Pestaña **General › WooCommerce** del formulario 20994 (si `woocommerce_enable=1`, el efectivo directo no es compatible y la API responderá `PAYMENT_NOT_COMPATIBLE`).
- Lista de países seleccionados en **Driving Zone** (en la captura, los listados muestran Colombia resaltada para origen y destino; el resto de la lista no se ve). Si "United States" no está seleccionado, la web tampoco debería permitir Nueva Jersey y la API tampoco.
- ID del vehículo "Automóvil" (se resuelve solo si el formulario tiene un único vehículo).
- Que `CHBSGoogleMapAPI::computeRoutes()` responda con la llave actual.

## Del formulario CHBS (capturas)
Booking Form ID **20994** "Agendamiento USA" · Service type **Distance** · Pago **Cash** (único habilitado, por defecto) · reCAPTCHA desactivado · Default Driver: ninguno · Reglas de precio: «Estados unidos fin de semana» y «Estados Unidos semana», Distance/One Way/Automóvil/GoRide, **US $2.05 por milla**, tarifa inicial heredada. Ninguna de estas configuraciones se modifica.
