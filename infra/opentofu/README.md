# Asistencia en AWS con OpenTofu

La configuración crea una VPC, una subred pública y dos EC2 Ubuntu 24.04 con IPv4 pública. Ambas instancias usan la llave `globomatics` y reciben el mismo [cloud-init](../cloud-init.yaml) con su rol correspondiente.

| Instancia | Tipo | IP privada | Acceso de aplicación |
|---|---|---|---|
| Cliente | `t3.micro` | `10.42.1.10` | HTTP desde Internet, puerto 80 |
| Backend | `t3.small` | `10.42.1.20` | API desde el grupo de seguridad del cliente, puerto 8090 |

SSH acepta una sola IPv4 pública en ambas instancias. MySQL escucha en el propio backend.

## Preparar y desplegar

Desde `cloud-init-2/infra/opentofu`, con OpenTofu 1.11 o posterior, AWS CLI autenticada, Bash, curl y GNU tar, ejecuta estos comandos en orden.

```bash
./preparar.sh
tofu init
tofu validate
tofu plan
tofu apply
tofu output
```

El preparador usa la cuenta activa y la región `us-east-2` por defecto. Detecta tu IPv4 pública, comprueba la llave `globomatics` y, si falta en esa región, importa la clave pública de `~/globomatics-ec2.pub`. Crea o reutiliza el bucket privado `asistencia-cloud-init-2-tofu-CUENTA-REGIÓN`, habilita el versionado y genera la configuración local de OpenTofu junto con el paquete de la aplicación.

`tofu apply` sube el paquete a ese bucket antes de crear las EC2. Cada instancia usa un perfil IAM con permiso de lectura sobre el objeto de la aplicación. El estado queda cifrado en S3 con bloqueo nativo y se guarda bajo `cloud-init-2/opentofu/terraform.tfstate`. [Backend S3 de OpenTofu](https://opentofu.org/docs/v1.11/language/settings/backends/s3/)

Usa el mismo perfil de AWS para el preparador y los comandos de OpenTofu. Si iniciaste sesión con `aws login`, el preparador configura un perfil local para que OpenTofu solicite las credenciales temporales a AWS CLI. Si ya habías preparado el directorio antes de iniciar sesión, vuelve a ejecutar `./preparar.sh` y luego `tofu init`. La sesión necesita permisos para preparar el bucket, gestionar los recursos del laboratorio y pasar el rol de descarga a EC2.

## Preparar desde Windows

En PowerShell 7.4 o posterior, con AWS CLI, OpenTofu y GNU tar, ejecuta estos comandos desde este directorio.

```powershell
.\preparar.ps1
tofu init
tofu validate
tofu plan
tofu apply
```

El preparador busca GNU tar en el PATH y en la instalación de Git for Windows.

## Volver a preparar

Ejecuta `./preparar.sh` de nuevo si cambia tu IP o si modificas el contenido de `app/` y quieres desplegarlo. Después revisa `tofu plan`. Cambiar el paquete cambia el User Data y puede reemplazar las EC2. Antes de reemplazar el backend, respalda MySQL si necesitas conservar sus datos.

Si corresponde, puedes definir `AWS_PROFILE`, `TF_VAR_region` o `GLOBOMATICS_PUBLIC_KEY` antes de ejecutar el preparador. Para indicar tu IP, define `TF_VAR_ssh_cidr` con tu IPv4 pública, con o sin `/32`. Ejecuta `unset TF_VAR_ssh_cidr` para volver a la detección automática. Si ya usabas un bucket para este mismo estado remoto, puedes conservarlo con `TOFU_STATE_BUCKET` y su región. Si vas a cambiar de bucket después de aplicar, ejecuta `tofu init -migrate-state` desde el directorio inicializado con el backend anterior, tras volver a ejecutar el preparador. Comprueba el estado con `tofu state list` antes de planificar. Si existe un estado local de un despliegue anterior, respáldalo y usa `tofu init -migrate-state` una sola vez para copiarlo a S3.

## Comprobar el arranque

```bash
ssh -i ~/globomatics-ec2 "ubuntu@$(tofu output -raw ip_cliente)" 'sudo cloud-init status --wait'
ssh -i ~/globomatics-ec2 "ubuntu@$(tofu output -raw ip_backend)" 'sudo cloud-init status --wait'
curl -i "$(tofu output -raw url_cliente)/api/me"
```

Un HTTP 401 en `/api/me` indica que la API responde sin una sesión iniciada. Abre la URL de `tofu output -raw url_cliente` en el navegador. El usuario inicial es `admin` y la contraseña se genera en el backend.

```bash
ssh -i ~/globomatics-ec2 "ubuntu@$(tofu output -raw ip_backend)" 'sudo cat /etc/asistencia/admin-password'
```

## Eliminar el laboratorio

Ejecuta `tofu destroy` desde este directorio. Al eliminar la EC2 del backend se pierde la base almacenada en su disco raíz. El bucket se conserva para mantener el estado y su historial. S3 cobra por las versiones almacenadas y las solicitudes. [Precios de Amazon S3](https://aws.amazon.com/s3/pricing/)
