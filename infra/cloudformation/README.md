# Asistencia en AWS con CloudFormation

La plantilla crea una VPC, una subred pública y dos EC2 Ubuntu 24.04 con IPv4 pública. Ambas usan la llave `globomatics` y reciben el mismo [cloud-init.yaml](../cloud-init.yaml) con su rol correspondiente.

| Instancia | Tipo | IP privada | Acceso de aplicación |
|---|---|---|---|
| Cliente | `t3.micro` | `10.42.1.10` | HTTP desde Internet, puerto 80 |
| Backend | `t3.small` | `10.42.1.20` | API desde el grupo de seguridad del cliente, puerto 8090 |

SSH acepta una sola IPv4 pública en ambas instancias. MySQL escucha en el propio backend.

## Preparar y validar

Desde `cloud-init-2/infra/cloudformation`, con AWS CLI autenticada, Bash, curl, Python 3, GNU tar y sha256sum, ejecuta:

```bash
./preparar.sh
aws cloudformation validate-template --region us-east-2 \
  --template-body file://.asistencia/template.yaml
```

El preparador detecta tu IPv4 pública, verifica la llave `globomatics` e importa `~/globomatics-ec2.pub` si falta en esa región. Crea o reutiliza el bucket privado `asistencia-cloud-init-2-cfn-CUENTA-REGIÓN`, habilita el versionado y sube el paquete cifrado de la aplicación. Después ensambla los archivos de red y cómputo en la plantilla principal e incorpora la IP de SSH, la ubicación del paquete y el User Data de ambas EC2.

Si usas otra región, configura `CFN_ASISTENCIA_REGION` y usa esa misma región en los comandos de AWS CLI. Puedes indicar una IPv4 con `CFN_ASISTENCIA_SSH_CIDR` o cambiar la ruta de la clave pública con `GLOBOMATICS_PUBLIC_KEY`. Usa la misma cuenta y perfil de AWS durante todo el proceso.

## Preparar desde Windows

En PowerShell 7.4 o posterior, con AWS CLI y GNU tar, ejecuta estos comandos desde este directorio.

```powershell
.\preparar.ps1
aws cloudformation validate-template --region us-east-2 --template-body file://.asistencia/template.yaml
aws cloudformation deploy --region us-east-2 --template-file .asistencia/template.yaml --stack-name asistencia-cloud-init --capabilities CAPABILITY_IAM --no-execute-changeset
```

Usa el ARN que devuelve el último comando para revisar y ejecutar el conjunto de cambios.

El preparador busca GNU tar en el PATH y en la instalación de Git for Windows.

## Revisar y desplegar

Genera un conjunto de cambios para revisar qué recursos se crearán o modificarán.

```bash
aws cloudformation deploy --region us-east-2 \
  --template-file .asistencia/template.yaml \
  --stack-name asistencia-cloud-init \
  --capabilities CAPABILITY_IAM \
  --no-execute-changeset
```

El comando imprime el ARN del conjunto. Sustitúyelo en los siguientes comandos.

```bash
aws cloudformation describe-change-set --region us-east-2 \
  --change-set-name 'ARN_DEL_CONJUNTO'

aws cloudformation execute-change-set --region us-east-2 \
  --change-set-name 'ARN_DEL_CONJUNTO'

aws cloudformation describe-stacks --region us-east-2 \
  --stack-name asistencia-cloud-init \
  --query 'Stacks[0].{Estado:StackStatus,Salidas:Outputs}'
```

El permiso `CAPABILITY_IAM` reconoce que la plantilla crea el rol de descarga. El rol solo permite leer el objeto del paquete. CloudFormation conserva el estado en el stack administrado por AWS y S3 aloja el paquete de la aplicación. [Comando deploy de AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/cloudformation/deploy.html)

## Cómo se relacionan los archivos

- `template.yaml` es la plantilla principal. Define los parámetros y las salidas del stack.
- `red.yaml` define la VPC, la subred, la ruta a Internet y los grupos de seguridad.
- `computo.yaml` define las dos EC2, el perfil IAM y los puntos donde se inserta el User Data.
- `preparar.sh` empaqueta la aplicación, ensambla los tres archivos e inserta en la plantilla dos copias del mismo `cloud-init.yaml`, una para cada rol.
- `.asistencia/template.yaml` es la plantilla generada que recibe CloudFormation. `Fn::Sub` completa la región y el origen del cliente. `Fn::Base64` codifica el User Data para EC2.

## Comprobar el arranque

Cuando el stack termine, usa los valores `IpCliente`, `IpBackend` y `UrlCliente` de sus salidas.

```bash
ssh -i ~/globomatics-ec2 ubuntu@IP_CLIENTE 'sudo cloud-init status --wait'
ssh -i ~/globomatics-ec2 ubuntu@IP_BACKEND 'sudo cloud-init status --wait'
curl -i http://IP_CLIENTE/api/me
```

Un HTTP 401 en `/api/me` indica que la API responde sin una sesión iniciada. El usuario inicial es `admin`. Consulta la contraseña generada en el backend.

```bash
ssh -i ~/globomatics-ec2 ubuntu@IP_BACKEND 'sudo cat /etc/asistencia/admin-password'
```

## Actualizar o eliminar el laboratorio

Si cambia tu IPv4, vuelve a ejecutar el preparador y revisa el conjunto de cambios. Cloud-init instala la aplicación durante el primer arranque. Si cambia el paquete, una actualización de User Data en las EC2 existentes puede reiniciarlas, y la instalación inicial solo se ejecuta en instancias nuevas. Para volver a desplegar la aplicación desde cero, recrea el stack y respalda antes MySQL si necesitas conservar los datos. [User Data de EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)

```bash
aws cloudformation delete-stack --region us-east-2 --stack-name asistencia-cloud-init
aws cloudformation wait stack-delete-complete --region us-east-2 --stack-name asistencia-cloud-init
```

Al eliminar la EC2 del backend se pierde la base de su disco raíz. El bucket y las versiones del paquete se conservan. [Precios de Amazon S3](https://aws.amazon.com/s3/pricing/)
