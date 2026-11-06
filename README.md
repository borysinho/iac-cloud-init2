# UAGRM Control de asistencia en AWS

Este laboratorio despliega la aplicación de control de asistencia en dos instancias EC2. Puedes aprovisionar la misma arquitectura con **OpenTofu, Pulumi o CloudFormation**. Las tres implementaciones comparten un solo [archivo de cloud-init](infra/cloud-init.yaml) y administran despliegues independientes.

## Arquitectura

Las dos instancias ejecutan Ubuntu 24.04 y tienen IPv4 pública. Comparten una subred dentro de una VPC y usan el par de claves `globomatics`. El acceso SSH a ambas se limita a la IPv4 pública del operador.

| Instancia | IP privada | Función |
|---|---|---|
| Cliente | `10.42.1.10` | Nginx publica la interfaz por HTTP y reenvía `/api` al backend. |
| Backend | `10.42.1.20` | Node.js ejecuta la API en el puerto `8090`. Solo el cliente puede acceder a ese puerto. MySQL escucha de forma local. |

La herramienta de infraestructura crea los recursos de AWS y entrega el User Data a cada EC2. Al arrancar, cloud-init lee el rol asignado, descarga el paquete privado de S3 con el perfil IAM de la instancia e instala los servicios correspondientes.

## Desplegar el laboratorio

Elige una herramienta y sigue su README. Los preparadores usan la sesión activa de AWS CLI y verifican el par de claves `globomatics` en la región elegida. Hay una versión Bash y una versión para PowerShell 7.4 o posterior. Cada guía indica los requisitos específicos.

| Herramienta | Comandos de despliegue | Estado |
|---|---|---|
| [OpenTofu](infra/opentofu/README.md) | `tofu init`, `tofu validate`, `tofu plan` y `tofu apply` | Backend S3 con bloqueo nativo |
| [Pulumi](infra/pulumi/README.md) | `pulumi preview` y `pulumi up` | Stack de Pulumi en S3 |
| [CloudFormation](infra/cloudformation/README.md) | `aws cloudformation validate-template`, revisión y ejecución del conjunto de cambios | Stack administrado por CloudFormation |

En Linux, Pulumi se prepara con `source ./preparar.sh`. En Windows, ejecuta `.\preparar.ps1` en PowerShell. En ambos casos, usa la misma terminal para los comandos de Pulumi.

Después del aprovisionamiento, espera a que `sudo cloud-init status --wait` termine en las dos instancias antes de abrir el sitio. Los README de cada herramienta incluyen los pasos para comprobar la aplicación y eliminar el laboratorio.

## Código y guías

- [Aplicación de control de asistencia](app/README.md)
- [Cómo OpenTofu usa cloud-init](docs/Gu%C3%ADa%20de%20OpenTofu%20y%20cloud-init.docx)
- [Cómo Pulumi usa cloud-init](docs/Gu%C3%ADa%20de%20Pulumi%20y%20cloud-init.docx)
- [Cómo CloudFormation usa cloud-init](docs/Gu%C3%ADa%20de%20CloudFormation%20y%20cloud-init.docx)
