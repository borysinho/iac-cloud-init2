# Arquitectura e independencia de las tres capas

La aplicación conserva el alcance de `Requerimientos_Control_Asistencia.pdf`: un módulo activo, marca durante todo el día programado, sin atrasos, historial personal, administración, importación y conservación de información anterior. No se añade consulta histórica ni se exige contraseña estudiantil.

## Responsabilidades y límites

| Capa | Responsabilidad | Dependencias permitidas |
|---|---|---|
| Presentación (`deploy/client/`, `public/`, `src/presentation/`) | Formularios, tablas, filtros visuales, solicitudes, configuración de API, tokens, sesión y traducción de errores a HTTP | Contrato del servicio; Express solo en el adaptador HTTP |
| Negocio (`src/services/`) | Acceso, roles, estados, marca, corrección, auditoría requerida y activación | Contrato del repositorio; reloj y funciones de contraseña/Excel inyectadas |
| Datos (`src/repositories/`, `database/`) | Consultas, persistencia, bloqueos, commit/rollback, claves y restricciones | MySQL; no depende de presentación o servicios |

`src/server.js` actúa como punto de composición y arranque. Puede conocer implementaciones de todas las capas para conectarlas, pero no contiene rutas, consultas ni reglas. Los scripts de instalación quedan fuera del flujo HTTP.

## Contrato de servicio

`createApp(service)` acepta un objeto con `login`, `dashboard`, `mark`, `correct`, `activities`, `prepareImport`, `activate`, `template` y `export`. Las operaciones reciben datos normales, no objetos Express. Los errores usan códigos `INVALID`, `UNAUTHENTICATED`, `FORBIDDEN` y `NOT_FOUND`; el adaptador HTTP los traduce a 400, 401, 403 y 404.

Las sesiones y los archivos preparados permanecen en memoria en presentación. `prepareImport` entrega datos validados; presentación conserva el borrador y `activate` recibe ese borrador explícitamente. Un reinicio de Node.js exige iniciar sesión y preparar nuevamente los archivos.

`dashboard` entrega una fila calculada por estudiante y fecha, incluso sin marca almacenada. Cada fila contiene `student_id`, `class_date_id`, `status`, `marked_at` y `canMark`. La interfaz no compara fechas para definir faltas. `canMark` controla el botón; el servicio vuelve a validar la fecha y el registro existente al marcar. Los registros derivados no se insertan en la base.

## Contrato de datos

`createAttendanceService({repository, clock, verifyPassword, parseExcel, workbookBuffer})` recibe sus dependencias. El repositorio debe ofrecer:

| Operaciones | Resultado o efecto |
|---|---|
| `activeModule(lock)`, `administrator(username)`, `identifyStudents(moduleId, identifier)` | Módulo activo, credenciales almacenadas y coincidencias estudiantiles |
| `students(moduleId, id?)`, `dates(moduleId)`, `records(moduleId, id?)` | Listas del módulo; registros persistidos sin estados derivados |
| `student(moduleId,id)`, `date(moduleId,day)`, `dateById(moduleId,id)`, `attendance(studentId,dateId)` | Entidad encontrada o ausencia |
| `insertMark`, `correct`, `audit` | Guardar marca, corrección o evento; corrección conserva hora original |
| `activities(moduleId,filter)` | Eventos del módulo filtrados, hasta 500 |
| `lockAdministrator`, `deactivateModules`, `createModule`, `insertStudent`, `insertDate` | Operaciones de activación; no eliminan históricos |
| `transaction(callback)` | Ejecutar callback con repositorio transaccional; devolver resultado o revertir ante error |

Los objetos usan los campos consumidos en `attendance.js`; el adaptador encapsula cómo obtenerlos. `createModule` devuelve el identificador creado. `audit` recibe un objeto con módulo, actor, acción, estudiante/registro afectado, valores anterior/nuevo y fecha/hora. El callback de `transaction` no recibe conexiones MySQL.

Para garantizar concurrencia, `activeModule(true)` bloquea el módulo dentro de la transacción de marca/corrección y `lockAdministrator` serializa las activaciones del mismo administrador. El esquema mantiene unicidad de módulo activo y asistencia por estudiante/fecha, así como claves foráneas entre entidades del mismo módulo. Cualquier adaptador sustituto debe conservar la atomicidad y estas garantías.

## Requisitos centralizados

| PDF | Implementación |
|---|---|
| RF-01/02 | `login` verifica estudiante activo o contraseña administrativa; autorización en servicios |
| RF-03, RN-03/04 | `mark` verifica día, inscripción y registro existente; persistencia y auditoría atómicas |
| RF-04/05, RN-05 | `attendanceState` calcula Falta al pasar el día; `dashboard` y exportación usan el mismo resultado |
| RF-06/08 | `dashboard` devuelve información permitida por rol; búsqueda, filtros y totales visuales |
| RF-07, RN-06/07 | `correct` exige administrador, valida entidades y audita antes/después conservando hora original |
| RF-09/10 | `audit` dentro de transacciones y `activities` restringido a administrador |
| RF-11/12 | `prepareImport` valida Excel; los horarios permanecen informativos |
| RF-13/15, RN-01/08 | `activate` exige confirmación, crea nuevo módulo sin asistencias y conserva datos anteriores |
| RF-14 | Adaptador MySQL y esquema persistente |
| RF-16/17/18 | Vista previa, exportación y mensajes conservados |

## Evidencia de independencia

`tests/services.test.js` ejecuta los casos de uso con repositorio en memoria y reloj fijo, sin iniciar Express ni conectarse a MySQL. Incluye rechazo de roles, fechas, duplicados, auditoría, rollback simulado y conservación de módulos. `tests/http.test.js` comprueba HTTP y sesiones con un servicio sustituto, sin base de datos. `tests/architecture.test.js` detecta imports prohibidos y SQL en negocio/presentación.

Las pruebas del repositorio en memoria demuestran reglas y límites, no sustituyen una prueba real de transacciones, claves y bloqueos en MySQL. La prueba integral pendiente se describe en `verificacion.md`.

## Cliente y backend independientes

El despliegue consta de dos servidores. El servidor cliente ejecuta únicamente Nginx (`deploy/client/`), sirve `public/` y reenvía `/api` al servidor backend. `public/config.js` define la URL relativa `/api`; no requiere un proceso Node.js ni variables de entorno en el navegador. La directiva `proxy_pass` en `deploy/client/asistencia.conf` indica la dirección privada del backend.

El servidor backend ejecuta la API Node.js/Express, las capas de negocio y datos y el gestor MySQL. API y MySQL son servicios separados dentro del mismo servidor. MySQL se instala como servicio local, escuchando en `127.0.0.1`, con almacenamiento persistente en su directorio de datos y un usuario exclusivo de la base. El esquema se inicializa manualmente con `npm run db:init` sin borrar datos. La API se ejecuta con Node.js, supervisada por la unidad systemd `deploy/backend/asistencia.service`. No se trasladan reglas de negocio al cliente.

El navegador envía solicitudes al mismo origen del cliente. Nginx conserva el prefijo `/api`, el token Bearer y las cargas/descargas; sobrescribe `X-Forwarded-For` con la IP observada. La API permite solo los orígenes configurados en `FRONTEND_ORIGINS` y solo confía en los proxies de `TRUSTED_PROXIES` para calcular la IP usada por el límite de acceso. La red/firewall debe restringir la API al servidor cliente.

La sesión usa `Authorization: Bearer TOKEN`, se guarda en `sessionStorage` y nunca se incorpora a enlaces de descarga. Plantillas y exportaciones utilizan `fetch` autenticado y un Blob temporal. Sesiones y borradores permanecen en memoria de una única instancia de API; reiniciar exige acceder y preparar los archivos nuevamente.

Los pasos de instalación manual, permisos, variables y configuración HTTPS se documentan en `README.md`. Nginx, la API y MySQL se administran como servicios del sistema en sus servidores respectivos. MySQL sigue siendo un proceso separado de Node.js.
