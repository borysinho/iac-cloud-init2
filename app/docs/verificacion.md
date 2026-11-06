# Verificación de la separación de capas

- La suite automatizada comprueba reglas, contraseñas, importaciones, casos de uso, límites de capas, configuración estática, CORS, sesiones, descargas y límite por IP detrás del proxy.
- Casos de uso probados con repositorio en memoria: acceso activo, roles, estados derivados, habilitación, marca única, hora original, auditoría, corrección de fechas pasadas, activación confirmada, conservación histórica e invalidación de acceso al módulo anterior.
- Rollback verificado en el repositorio de prueba ante fallo de auditoría o inserción durante activación.
- Adaptador HTTP probado con servicio sustituto: CORS permitido/rechazado, OPTIONS, token Bearer, dashboard, descargas, traducción de errores y cierre de sesión.
- `npm run check`: sintaxis de composición, presentación, negocio, datos y frontend.
- No se modificó el esquema ni se ejecutó inicialización/migración de datos.

Ejecutar `npm test` y `npm run check`. La prueba HTTP abre un puerto temporal en `127.0.0.1`; el entorno debe permitir conexiones locales.

## Estado de la verificación del despliegue manual

La configuración actual incluye un archivo Nginx y una unidad systemd para instalar manualmente. Las 25 pruebas automatizadas y `npm run check` aprobaron tras retirar los archivos de despliegue anteriores. Nginx no está instalado en este entorno, por lo que `nginx -t` debe ejecutarse en el servidor cliente. La revisión anterior de acceso, descarga y persistencia con MySQL real no acredita la instalación nativa ni los permisos de servicios del servidor destino. Deben comprobarse siguiendo la lista de despliegue de abajo.

La instalación anterior de dependencias informó dos vulnerabilidades moderadas; las versiones se conservaron sin actualización automática.

## Verificación funcional completa pendiente

La prueba de despliegue con MySQL real no sustituye la verificación de todos los flujos ni de bloqueos y concurrencia. Para completar la revisión funcional configure `.env.backend`, inicialice con `npm run db:init` e inicie con `npm run start:backend`. Configure `proxy_pass` en `deploy/client/asistencia.conf`, copie los archivos públicos y valide/inicie Nginx siguiendo el README.

1. Importe estudiantes y fechas de ayer, hoy y mañana. Compruebe Falta/Pendiente y botón habilitado solo hoy sin registro.
2. Marque hoy y repita la solicitud: una sola asistencia y una sola actividad.
3. Corrija desde administración, incluida una fecha pasada. Verifique valores anterior/nuevo y conservación de hora original.
4. Compruebe historial, filtros, totales y que el Excel exportado coincida con los estados de pantalla.
5. Active otro módulo con confirmación. Compruebe que inicia sin marcas y los datos anteriores siguen almacenados. El estudiante anterior debe volver a ingresar.
6. Reinicie Node.js: los datos persisten, la sesión y borradores de importación deben prepararse nuevamente.

La verificación visual previa de la pantalla de acceso consta en las capturas existentes en `tmp/`; no constituye una prueba visual de los flujos modificados en esta refactorización.

## Prueba de despliegue en dos servidores

1. Backend: instale Node.js y MySQL, cree el usuario de base, configure `.env.backend`, instale dependencias e inicialice el esquema. Instale e inicie `asistencia.service` según el README. Confirme que MySQL escucha solo en la interfaz local y que el usuario del servicio puede leer la aplicación/configuración.
2. Cliente: instale Nginx, copie los archivos públicos y `deploy/client/asistencia.conf`, ajuste IPs/puertos/rutas y ejecute `nginx -t` antes de iniciar o recargar Nginx.
3. Abra la URL del cliente autorizada en `FRONTEND_ORIGINS`. Compruebe que `config.js` contiene `/api`, que los archivos cargan y que el navegador hace solicitudes al mismo origen.
4. Compruebe ingreso, importaciones (incluido un archivo válido mayor de 1 MB), descargas de plantillas/exportación, marcación y corrección.
5. Compruebe que el límite de acceso distingue IPs reales pasando por Nginx. Si hay un balanceador delante, configure primero sus direcciones de confianza en Nginx.
6. Detenga solo la API: la interfaz sigue disponible y las operaciones indican error. Reinicie, vuelva a ingresar y confirme que los datos persisten.
7. Reinicie API y MySQL mediante sus servicios del sistema y compruebe que las asistencias persisten. Verifique también el arranque automático después de reiniciar el equipo.

El despliegue en dos equipos físicos y la terminación HTTPS requieren verificación en el entorno destino. Las pruebas unitarias utilizan puertos temporales y contratos sustitutos.
