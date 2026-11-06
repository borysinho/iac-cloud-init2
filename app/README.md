# UAGRM · Control de asistencia

Aplicación en tres capas con **cliente ligero y backend que se levantan por separado**. El navegador consume `/api` a través de Nginx en el servidor cliente. El equipo backend ejecuta Node.js/Express y MySQL; el cliente no necesita MySQL ni ejecuta reglas de negocio.

## Organización de esta copia

Esta carpeta contiene únicamente la aplicación. La infraestructura se preparará por separado en [`../infra/`](../infra/README.md), con directorios para OpenTofu, Pulumi y CloudFormation. La configuración de los servidores con cloud-init se incorporará en los siguientes pasos.

Los archivos de Nginx y systemd se conservan en `deploy/` porque forman parte del despliegue de la aplicación. La guía `docs/despliegue-manual-aws.md` se conserva como referencia histórica del laboratorio original; sus direcciones y comandos de infraestructura no corresponden a este nuevo entorno.

No se incluyen credenciales locales ni dependencias instaladas. Para preparar una instalación, utiliza `.env.backend.example` como plantilla e instala las dependencias con `npm ci` dentro de `app/`.

## Despliegue manual en dos servidores

- **Servidor cliente:** instala Nginx y sirve `public/`. Reenvía `/api` a la IP privada del backend. No requiere Node.js, npm ni MySQL.
- **Servidor backend:** instala Node.js 24, npm y MySQL 8.0 o superior. Ejecuta la API (negocio y repositorios) y MySQL como servicios separados del mismo equipo.

Los ejemplos usan cliente `192.168.1.20` y backend `192.168.1.30:8090`. Sustituye estas direcciones por las reales. Los comandos de instalación de paquetes y el nombre del servicio MySQL dependen del sistema operativo. Los archivos de servicio incluidos están preparados para Linux con systemd. La instalación se realiza manualmente; el proyecto no instala ni modifica servicios del sistema por sí solo.

### 1. Backend: MySQL y configuración

Instala e inicia MySQL en el servidor backend. Configura `bind-address=127.0.0.1` en su sección `[mysqld]` y reinicia su servicio: la base solo debe aceptar conexiones locales. Si MySQL habilita otros puertos, como el de X Protocol, restringe también su escucha al equipo local o deshabilítalos si no se utilizan.

En una sesión administrativa de MySQL, crea la base y un usuario exclusivo de la aplicación. Elige una contraseña propia y utiliza ese mismo valor en `.env.backend`:

```sql
CREATE DATABASE IF NOT EXISTS uagrm_asistencia
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'asistencia'@'127.0.0.1' IDENTIFIED BY 'REEMPLAZAR_POR_CLAVE_PROPIA';
GRANT ALL PRIVILEGES ON uagrm_asistencia.* TO 'asistencia'@'127.0.0.1';
```

La cuenta solo tiene permisos sobre esa base. Si ya existe, administra su contraseña con `ALTER USER`; no elimines ni recrees la base existente.

Coloca en `/opt/asistencia/` los archivos `package.json`, `package-lock.json` y los directorios `src/`, `scripts/`, `database/` y `deploy/backend/`. Copia también `.env.backend.example` si vas a usarlo como plantilla. Para otra ruta, ajusta la unidad systemd. Dentro de esa carpeta:

```bash
cp .env.backend.example .env.backend
# Edita las IPs, el usuario y las contraseñas antes de continuar.
npm ci --omit=dev
npm run db:init
npm start
```

`npm start` y `npm run start:backend` ejecutan la API en primer plano. Detén esa ejecución con Ctrl+C antes de iniciarla como servicio. `npm run dev` y `npm run dev:backend` activan la recarga para desarrollo.

Variables de `.env.backend`:

| Variable | Configuración |
|---|---|
| `BACKEND_HOST`, `PORT` | IP privada local del backend y puerto de API; ejemplo `192.168.1.30`, `8090` |
| `FRONTEND_ORIGINS` | Origen exacto del cliente; ejemplo `http://192.168.1.20` |
| `TRUSTED_PROXIES` | IP del Nginx vista por la API; ejemplo `192.168.1.20` |
| `DB_HOST`, `DB_PORT` | MySQL local: `127.0.0.1`, `3306` |
| `DB_USER`, `DB_PASSWORD`, `DB_NAME` | Usuario dedicado, su contraseña y base |
| `ADMIN_USER`, `ADMIN_PASSWORD` | Cuenta inicial de administración; contraseña de al menos 12 caracteres |
| `INSTITUTION_TIMEZONE` | `America/La_Paz` |

`npm run db:init` crea las tablas y el administrador sin borrar datos. Si el administrador ya existe, conserva su contraseña; cambiar la variable no modifica esa cuenta. La inicialización se ejecuta manualmente, con MySQL disponible, antes del primer arranque. MySQL guarda los datos en su directorio de almacenamiento habitual; configura copias de seguridad de la base.

### 2. Backend como servicio systemd

Se incluye `deploy/backend/asistencia.service`. Crea un usuario de sistema `asistencia` sin acceso interactivo; en Debian/Ubuntu puedes usar `sudo useradd --system --user-group --home-dir /opt/asistencia --no-create-home --shell /usr/sbin/nologin asistencia` si no existe. Permite a ese usuario leer la aplicación y sus dependencias. Protege `.env.backend`, por ejemplo con propietario `root:asistencia` y permisos `640`.

Ajusta `User`, `Group`, `WorkingDirectory` y las rutas de `ExecStart` en el archivo según tu instalación. `ExecStart` requiere la ruta absoluta de Node.js 24: consulta `command -v node`. Una instalación dentro de un directorio personal no será accesible con `ProtectHome=true`; utiliza una instalación del sistema accesible al usuario del servicio. Ajusta `After` al nombre real de tu servicio MySQL (`mysql.service` o `mysqld.service`). Inicia MySQL antes de iniciar la API; la unidad no instala ni inicializa la base.

```bash
sudo cp deploy/backend/asistencia.service /etc/systemd/system/asistencia.service
sudo systemctl daemon-reload
sudo systemctl enable --now asistencia
sudo systemctl status asistencia
```

Para reiniciar después de cambios usa `sudo systemctl restart asistencia`. Para consultar registros usa `sudo journalctl -u asistencia -n 100 --no-pager`. Activa también el arranque automático de MySQL usando su nombre de servicio. Las sesiones y borradores están en memoria de una sola instancia de API y se pierden al reiniciarla; los registros de asistencia permanecen en MySQL.

### 3. Cliente: Nginx y archivos estáticos

Instala Nginx en el servidor cliente. Desde la copia del proyecto en ese servidor:

```bash
sudo install -d -m 755 /var/www/asistencia
sudo install -m 644 public/index.html public/app.js public/styles.css public/config.js /var/www/asistencia/
sudo cp deploy/client/asistencia.conf /etc/nginx/conf.d/asistencia.conf
```

Edita `/etc/nginx/conf.d/asistencia.conf`: ajusta `listen` (80 en el ejemplo), `server_name`, `root` y `proxy_pass` con la dirección privada real del backend, **sin `/api` ni barra final**. La regla conserva el prefijo `/api` al reenviar solicitudes. La configuración debe estar incluida desde el bloque `http` principal de Nginx y no competir con otro servidor predeterminado en ese puerto; adapta la ubicación del archivo a tu distribución.

```bash
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

Abre `http://192.168.1.20`. `public/config.js` define `/api`; la dirección del backend se configura directamente en `proxy_pass`. No hay un servidor Node para el cliente ni pasos de compilación. Nginx no utiliza `.env.frontend`; cualquier archivo local antiguo de ese nombre queda sin efecto. Para actualizar la interfaz, vuelve a copiar los cuatro archivos; si cambias la configuración, valida y recarga Nginx.

### Red y HTTPS

Autoriza el puerto de la API únicamente desde el servidor cliente mediante el firewall/red privada. Mantén MySQL escuchando solo en la interfaz local del backend. El navegador se conecta al cliente y nunca directamente a MySQL.

La configuración incluida sirve HTTP para pruebas/red privada. Antes de publicar, configura HTTPS en Nginx o en el balanceador de entrada, dominio y certificado; cambia `FRONTEND_ORIGINS` al origen real, por ejemplo `https://asistencia.ejemplo.com`. El navegador sigue usando `/api` en el mismo origen. Si Nginx → API cruza una red pública, configura TLS verificado o una VPN.

Si hay un balanceador delante de Nginx, configura `set_real_ip_from`/`real_ip_header` únicamente para sus direcciones de confianza. Nginx sobrescribe `X-Forwarded-For` con la IP observada; Express solo confía en las direcciones de `TRUSTED_PROXIES` para limitar intentos por IP real.

Nginx conserva las cabeceras de seguridad, permite peticiones de hasta 4 MB para los archivos Excel de hasta 3 MB más el formulario y limita a tres segundos la conexión al backend cuando no está disponible. No copies credenciales ni archivos del backend al directorio público del cliente.

## Primera utilización y Excel

1. Ingresa como administrador y abre Nuevo módulo.
2. Descarga las plantillas y carga los estudiantes y fechas reales.
3. Importa ambos archivos, revisa los datos y confirma la activación.
4. El estudiante puede ingresar por registro o correo del módulo activo y marcar en el día programado.

Solo archivos `.xlsx`, hasta 3 MB y 5000 filas, primera hoja y encabezados en primera fila. Guarda el registro como texto para conservar ceros iniciales. Se rechazan fórmulas, campos inválidos y registros/fechas duplicados; ningún archivo se importa parcialmente.

| Estudiantes | Fechas |
|---|---|
| Número de registro | Fecha |
| Nombre completo | Hora inicio |
| Correo electrónico | Hora fin |

Fechas `DD/MM/AAAA` o `AAAA-MM-DD`; horas `HH:MM` o celdas de hora de Excel. La hora final debe ser posterior a la inicial; los horarios son informativos. Las descargas e importaciones se realizan contra la API remota con la sesión autenticada.

## Reglas y alcance

- Un módulo activo y una marca por estudiante/fecha.
- Marcas durante todo el día de clase, sin atrasos ni tolerancias; fecha/hora del backend en `America/La_Paz`.
- Fechas pasadas sin marca se muestran como Falta; hoy y fechas futuras sin registro, como Pendiente. Los estados son calculados en negocio y usados por pantalla y exportación.
- El estudiante no edita asistencias. Solo el administrador puede corregir cualquier fecha del módulo activo; se conserva la hora original y se auditan valores anterior/nuevo.
- Marcas, correcciones y auditoría se guardan en transacciones.
- Activar otro módulo exige confirmación, conserva los datos anteriores e inicia sin asistencias. No se añade consulta histórica.
- Búsquedas, filtros, totales, vista previa y exportación Excel disponibles. Actividades: hasta 500 resultados; paginación visual de 20 filas.
- Sesión de ocho horas en backend, token en `sessionStorage` del navegador. Recargar conserva la sesión en esa pestaña; cerrar la pestaña elimina su token y reiniciar el backend pierde las sesiones y borradores.
- RF-01 mantiene el ingreso estudiantil por correo o registro sin contraseña. El administrador usa contraseña propia almacenada con scrypt y salt.

## Arquitectura

```text
deploy/client/             Nginx: archivos estáticos y proxy a /api
deploy/backend/            Unidad systemd para la API; MySQL se instala localmente
public/                    Presentación y config.js estático; conexión por /api
src/presentation/app.js    Adaptador HTTP del backend: CORS, token y respuestas
src/services/              Negocio: casos de uso, permisos y reglas
src/repositories/          Datos: consultas MySQL y transacciones
src/server.js              Composición y arranque exclusivo del backend
database/schema.sql        Esquema y restricciones
scripts/init-db.js         Inicialización sin borrar datos
docs/arquitectura.md        Contratos y trazabilidad con requisitos
docs/diagramas.md          Diagramas de capas y despliegue
```

Las tres capas lógicas se despliegan en dos aplicaciones: presentación en el cliente y negocio/datos en el backend. El adaptador HTTP también es una frontera de presentación, alojada junto al negocio. Negocio no depende de Express o MySQL; recibe el repositorio por contrato. Datos no depende de negocio ni presentación. El punto de composición conecta sus implementaciones.

## Validación

```bash
npm test
npm run check
```

Las pruebas HTTP abren puertos temporales locales. Se verifican reglas con repositorio en memoria, API con servicio sustituto, configuración estática del cliente, CORS, proxy de confianza, tokens y descargas. La prueba con MySQL real y dos equipos se describe en `docs/verificacion.md`.

Si falla la conexión, comprueba `proxy_pass` en Nginx, el firewall entre servidores, disponibilidad de la API y que el origen del cliente esté en `FRONTEND_ORIGINS`. Consulta `journalctl -u asistencia`, los registros de MySQL y los archivos de acceso/error de Nginx según tu instalación. Comprueba la configuración con `nginx -t`.
