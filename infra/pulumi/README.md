# Asistencia en AWS con Pulumi

Pulumi crea una VPC, una subred pública y dos EC2 Ubuntu 24.04 con IPv4 pública. Ambas instancias usan la llave `globomatics` y reciben el mismo [cloud-init.yaml](../cloud-init.yaml) con su rol correspondiente.

| Instancia | Tipo | IP privada | Acceso de aplicación |
|---|---|---|---|
| Cliente | `t3.micro` | `10.42.1.10` | HTTP desde Internet, puerto 80 |
| Backend | `t3.small` | `10.42.1.20` | API desde el grupo de seguridad del cliente, puerto 8090 |

SSH acepta una sola IPv4 pública en ambas instancias. MySQL escucha en el propio backend.

## Preparar y desplegar

Desde `cloud-init-2/infra/pulumi`, con Bash, Pulumi CLI, Node.js 24, npm, AWS CLI autenticada, curl, OpenSSL y GNU tar, ejecuta estos comandos en la misma terminal.

```bash
source ./preparar.sh
pulumi preview
pulumi up
pulumi stack output
```

`source` carga en esa terminal el backend S3, la configuración de AWS y la frase de cifrado del stack. Si abriste una terminal nueva o ejecutaste `./preparar.sh` directamente, carga el entorno ya generado sin volver a preparar el laboratorio.

```bash
source ./.asistencia/entorno.sh
pulumi preview
```

Si `pulumi preview` pide un token de Pulumi Cloud, cancela con Ctrl+C y carga el entorno de este directorio con el comando anterior.

El preparador usa `us-east-2` por defecto. Detecta tu IPv4 pública, verifica la llave `globomatics` e importa `~/globomatics-ec2.pub` si falta en la región. Crea o reutiliza el bucket privado `asistencia-cloud-init-2-pulumi-CUENTA-REGIÓN`, activa el versionado, instala las dependencias, genera el paquete de la aplicación y selecciona el stack `laboratorio`. Si usas `aws login`, configura un perfil local que solicita las credenciales temporales a AWS CLI.

`pulumi up` sube el paquete al bucket antes de crear las EC2. El perfil IAM de las instancias permite leer únicamente ese objeto. Pulumi guarda el estado y sus archivos de bloqueo bajo el prefijo `cloud-init-2/pulumi`. Este stack administra sus propios recursos, separados del despliegue de OpenTofu. [Estado y backends de Pulumi](https://www.pulumi.com/docs/iac/concepts/state-and-backends/)

Conserva una copia segura de `.asistencia/passphrase` para recuperar los secretos del stack. Para usar una copia existente, define `PULUMI_ASISTENCIA_PASSPHRASE_FILE` con su ruta antes de cargar el preparador.

## Preparar desde Windows

En PowerShell 7.4 o posterior, con AWS CLI, Pulumi, Node.js 24, npm y GNU tar, ejecuta estos comandos desde este directorio y en la misma terminal.

```powershell
.\preparar.ps1
pulumi preview
pulumi up
pulumi stack output
```

En una terminal nueva, recarga el entorno generado antes de ejecutar Pulumi, incluido `pulumi destroy`.

```powershell
. .\.asistencia\entorno.ps1
```

El preparador busca GNU tar en el PATH y en la instalación de Git for Windows.

## Archivos

- `Pulumi.yaml` identifica el proyecto y selecciona el entorno de Node.js.
- `index.js` lee la configuración, conecta la red con el cómputo y exporta las IP públicas.
- `red.js` define la VPC, la subred, las rutas y los grupos de seguridad.
- `computo.js` publica el paquete, define los permisos de descarga y prepara el User Data de las EC2.

## Actualizar el laboratorio

Vuelve a ejecutar `source ./preparar.sh` si cambia tu IP o el contenido de `app/`. Después revisa `pulumi preview`. Cambiar el paquete cambia el User Data y puede reemplazar las instancias. Si necesitas conservar la base, respalda MySQL antes de reemplazar el backend.

Puedes definir `AWS_PROFILE`, `PULUMI_ASISTENCIA_REGION`, `PULUMI_ASISTENCIA_SSH_CIDR` o `GLOBOMATICS_PUBLIC_KEY` antes de cargar el preparador. La IPv4 de SSH puede indicarse con o sin `/32`. Si ya tienes un bucket dedicado para este stack, indica su nombre con `PULUMI_ASISTENCIA_BUCKET` y conserva el mismo destino de estado entre ejecuciones.

## Comprobar el arranque

Al terminar `pulumi up`, cloud-init puede seguir configurando las EC2. Durante ese intervalo, el cliente puede mostrar la página predeterminada de Nginx. Espera a que `cloud-init status --wait` termine en ambas instancias antes de abrir el sitio.

```bash
ssh -i ~/globomatics-ec2 "ubuntu@$(pulumi stack output ip_cliente)" 'sudo cloud-init status --wait'
ssh -i ~/globomatics-ec2 "ubuntu@$(pulumi stack output ip_backend)" 'sudo cloud-init status --wait'
curl -i "$(pulumi stack output url_cliente)/api/me"
```

Un HTTP 401 en `/api/me` indica que la API responde sin una sesión iniciada. El usuario inicial es `admin` y la contraseña se genera en el backend.

```bash
ssh -i ~/globomatics-ec2 "ubuntu@$(pulumi stack output ip_backend)" 'sudo cat /etc/asistencia/admin-password'
```

## Eliminar el laboratorio

Desde `cloud-init-2/infra/pulumi`, carga el entorno del stack, revisa los recursos que Pulumi propone eliminar y confirma cuando lo solicite.

```bash
source ./.asistencia/entorno.sh
pulumi destroy
```

Al eliminar la EC2 del backend se pierde la base almacenada en su disco raíz. El bucket se conserva para mantener el estado y su historial. S3 cobra por las versiones almacenadas y las solicitudes. [Precios de Amazon S3](https://aws.amazon.com/s3/pricing/)
