# goride-rider-api — instalación, pruebas y reversa

**Nada de esto se ha instalado ni ejecutado en producción.** Este paquete solo contiene código, pruebas aisladas y guía. No hay operaciones de base de datos que ejecutar: el plugin no crea tablas ni opciones permanentes.

## 0. Lectura previa (solo SELECT en phpMyAdmin; no modifica nada)
Cambia `wp_` si tu prefijo es otro. Pega los resultados (sin contraseñas) para cerrar los puntos pendientes:
```sql
SELECT meta_key, meta_value FROM wp_postmeta
WHERE post_id = 20994 AND meta_key IN (
 'chbs_woocommerce_enable','chbs_woocommerce_add_to_cart_enable','chbs_payment_id','chbs_service_type_id',
 'chbs_driving_zone_restriction_pickup_location_enable','chbs_driving_zone_restriction_pickup_location_country',
 'chbs_driving_zone_restriction_dropoff_location_enable','chbs_driving_zone_restriction_dropoff_location_country',
 'chbs_driving_zone_restriction_location_field_relation_type',
 'chbs_location_fixed_pickup_service_type_1','chbs_location_fixed_dropoff_service_type_1');
```
```sql
SELECT ID, post_title, post_status FROM wp_posts WHERE post_type = 'chbs_vehicle';
```

## 1. Copia de seguridad (cPanel › Administrador de archivos)
1. No se reemplaza ningún archivo existente, así que no hace falta respaldar plugins. Aun así, descarga una copia de `wp-content/plugins/` (Comprimir › Descargar) y exporta la base con «Copias de seguridad» de HostGator antes de activar.
2. Anota el sha256 de cada archivo de `goride-rider-api/` (lista en `SHA256SUMS.txt`).

## 2. Instalación
1. Sube la carpeta `goride-rider-api/` completa a `wp-content/plugins/` (Administrador de archivos › Cargar `goride-rider-api.zip` › Extraer).
2. WordPress › Plugins › activar **GoRide Rider API**. Debe verse junto a goride-api, goride-live y CHBS activos.
3. (Opcional) `wp-config.php`, antes de «That's all»:
```php
define('GORIDE_RIDER_VEHICLE_ID', 123);   // solo si el formulario tiene más de un vehículo
```
El ID del formulario (20994) y los demás valores ya vienen por defecto.

## 3. Pruebas SIN riesgo (no crean reservas, no tocan conductores)
Con una cuenta de pasajero de prueba (PowerShell):
```powershell
$r = Invoke-RestMethod -Method Post -Uri "https://goride.website/wp-json/goride/v2/auth/login" -ContentType "application/json" -Body '{"email":"TU_CORREO","password":"TU_CLAVE"}'
$h = @{ Authorization = "Bearer " + $r.data.access_token }
Invoke-RestMethod -Uri "https://goride.website/wp-json/goride-rider/v1/config" -Headers $h | ConvertTo-Json -Depth 6
```
Esperado: `ready: true`. Si `blocking_reasons` trae `payment_not_compatible`, **detente y avísame**: no se tocará la configuración sin tu autorización.
```powershell
$b = '{"pickup":{"lat":40.7357,"lng":-74.1724,"address":"Newark, NJ"},"dropoff":{"lat":40.7128,"lng":-74.0060,"address":"New York, NY"},"passengers":1}'
Invoke-RestMethod -Method Post -Uri "https://goride.website/wp-json/goride-rider/v1/quotes" -Headers $h -ContentType "application/json" -Body $b | ConvertTo-Json -Depth 6
```
Compara `price.total` con el precio que muestra el formulario web para la misma ruta (US $2.05/milla según tus reglas). Si no coincide, no sigas.
```powershell
Invoke-RestMethod -Uri "https://goride.website/wp-json/goride-rider/v1/trips/active" -Headers $h
```
Esperado: `trip: null`.
Control de seguridad (debe dar 401): llamar `/config` sin cabecera `Authorization`.

## 4. Prueba con reserva real (SOLO con tu autorización expresa)
`POST /bookings` crea una reserva real y **dispara el despacho real a conductores**. Antes: pon a los conductores de prueba fuera de línea o avísales. No la automatices. Pasos y criterios los defines tú; la app tiene la misma prueba en su lista manual.

## 5. Reversa
1. Plugins › **Desactivar** «GoRide Rider API» (las rutas desaparecen al instante) y, si quieres, Eliminar.
2. No hay tablas ni opciones permanentes. Reservas ya creadas por la app conservan sus metas (`_goride_user_id`…): son inofensivas.
3. Candados huérfanos (si hubo un corte): `DELETE FROM wp_options WHERE option_name LIKE 'goride\_rider\_lk\_%' OR option_name LIKE 'goride\_rider\_uk\_%';` (solo si el servicio estuvo desactivado).

## 6. Pruebas aisladas incluidas (sin WordPress, sin red, sin base de datos)
`php tests/run_tests.php` → **121 pruebas correctas, 0 fallidas** (PHP 8.3 del entorno de desarrollo; producción usa 8.4 — recomendado repetir `php -l` allí). Incluyen: estados, firma de cotización (alterada/otro usuario/vencida), zona, precio no editable por el cliente, doble toque, solicitudes simultáneas, candados huérfanos, reintento tras fallo de CHBS, propiedad estricta, privacidad del conductor, cancelación fuera de estado, límite de frecuencia, salida PHP impresa por CHBS, y aislamiento (el plugin no escribe estado de viaje, no usa namespaces existentes, no toca despacho/FCM/tablas). Mutaciones comprobadas: quitar propiedad, recálculo de precio, estado cancelable o fallo cerrado de zona hace fallar pruebas.
**Lo que estas pruebas NO prueban:** `ChbsGatewayLive` (cálculo de ruta/precio y `sendBooking()` reales de CHBS, `AuthMiddleware` real, `rest_do_request` real). Eso solo se valida en tu servidor con los pasos 3 y 4.
