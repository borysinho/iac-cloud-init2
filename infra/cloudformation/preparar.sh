#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""

region=${CFN_ASISTENCIA_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}}
cuenta=$(aws sts get-caller-identity --region "$region" --query Account --output text)
bucket=${CFN_ASISTENCIA_BUCKET:-}
if [[ -z $bucket || $bucket == nombre-unico-del-bucket-de-estado ]]; then
  bucket="asistencia-cloud-init-2-cfn-$cuenta-$region"
fi
if [[ ! $cuenta =~ ^[0-9]{12}$ || ! $region =~ ^[a-z0-9-]+$ ||
      ! $bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  printf 'Revisa la cuenta, la región y el nombre del bucket.\n' >&2
  exit 1
fi

ssh_cidr=${CFN_ASISTENCIA_SSH_CIDR:-}
ssh_cidr=${ssh_cidr#"${ssh_cidr%%[![:space:]]*}"}
ssh_cidr=${ssh_cidr%"${ssh_cidr##*[![:space:]]}"}
octeto='(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
ipv4="($octeto\\.){3}$octeto"

if [[ -z $ssh_cidr || $ssh_cidr == TU_IPV4_PUBLICA/32 ]]; then
  if ! ip_publica=$(curl -fsS -4 --max-time 15 https://checkip.amazonaws.com) ||
     [[ ! $ip_publica =~ ^[[:space:]]*($ipv4)[[:space:]]*$ ]]; then
    printf 'No se pudo detectar la IPv4 pública. Define CFN_ASISTENCIA_SSH_CIDR con tu IPv4 pública y vuelve a ejecutar ./preparar.sh.\n' >&2
    exit 1
  fi
  ssh_cidr="${BASH_REMATCH[1]}/32"
elif [[ $ssh_cidr =~ ^$ipv4(/32)?$ ]]; then
  ssh_cidr="${ssh_cidr%/32}/32"
else
  printf 'CFN_ASISTENCIA_SSH_CIDR debe ser una IPv4 pública, con o sin /32. Ejecuta unset CFN_ASISTENCIA_SSH_CIDR para detectarla automáticamente.\n' >&2
  exit 1
fi

if ! clave=$(aws ec2 describe-key-pairs --region "$region" --key-names globomatics 2>&1); then
  if [[ $clave != *InvalidKeyPair.NotFound* ]]; then
    printf '%s\n' "$clave" >&2
    exit 1
  fi
  clave_publica=${GLOBOMATICS_PUBLIC_KEY:-"$HOME/globomatics-ec2.pub"}
  if [[ ! -r $clave_publica ]]; then
    printf 'Indica la ruta a la clave pública existente en GLOBOMATICS_PUBLIC_KEY.\n' >&2
    exit 1
  fi
  aws ec2 import-key-pair --region "$region" --key-name globomatics \
    --public-key-material "fileb://$clave_publica" >/dev/null
fi

if ! acceso=$(aws s3api head-bucket --bucket "$bucket" --region "$region" \
  --expected-bucket-owner "$cuenta" 2>&1); then
  if [[ $acceso != *'(404)'* && $acceso != *NoSuchBucket* ]]; then
    printf '%s\n' "$acceso" >&2
    exit 1
  fi
  if [[ $region == us-east-1 ]]; then
    aws s3api create-bucket --bucket "$bucket" --region "$region" >/dev/null
  else
    aws s3api create-bucket --bucket "$bucket" --region "$region" \
      --create-bucket-configuration "LocationConstraint=$region" >/dev/null
  fi
fi

ubicacion=$(aws s3api get-bucket-location --bucket "$bucket" --region "$region" \
  --expected-bucket-owner "$cuenta" --query LocationConstraint --output text)
case "$ubicacion" in
  None) ubicacion=us-east-1 ;;
  EU) ubicacion=eu-west-1 ;;
esac
if [[ $ubicacion != "$region" ]]; then
  printf 'El bucket %s está en %s. Usa esa región o elige otro bucket.\n' "$bucket" "$ubicacion" >&2
  exit 1
fi

aws s3api put-public-access-block --bucket "$bucket" --region "$region" \
  --expected-bucket-owner "$cuenta" \
  --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws s3api put-bucket-versioning --bucket "$bucket" --region "$region" \
  --expected-bucket-owner "$cuenta" --versioning-configuration Status=Enabled

mkdir -p .asistencia
temporal=$(mktemp -d .asistencia/preparar.XXXXXX)
trap 'rm -rf -- "$temporal"' EXIT

# Un paquete idéntico conserva la misma huella aunque se ejecute el script otra vez.
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$temporal/app.tar.gz" \
  -C ../../app package.json package-lock.json public src scripts database


huella=$(sha256sum "$temporal/app.tar.gz")
clave_app="cloud-init-2/cloudformation/app/${huella%% *}.tar.gz"
if ! aws s3api head-object --bucket "$bucket" --key "$clave_app" --region "$region" \
  --expected-bucket-owner "$cuenta" >/dev/null 2>&1; then
  aws s3 cp "$temporal/app.tar.gz" "s3://$bucket/$clave_app" --region "$region" \
    --sse AES256 --content-type application/gzip --only-show-errors
fi

python3 - "$ssh_cidr" "$bucket" "$clave_app" "$temporal/template.yaml" <<'PYTHON'
import sys
from pathlib import Path
from textwrap import indent

ssh_cidr, bucket, clave, destino = sys.argv[1:]
plantilla = Path("template.yaml").read_text(encoding="utf-8")
for archivo in ("red.yaml", "computo.yaml"):
    marcador = f"  # @{archivo}"
    if plantilla.count(marcador) != 1:
        raise SystemExit(f"Marcador de recursos ausente o duplicado para {archivo}.")
    recursos = Path(archivo).read_text(encoding="utf-8").rstrip()
    plantilla = plantilla.replace(marcador, indent(recursos, "  "))

cloud_init = Path("../cloud-init.yaml").read_text(encoding="utf-8")
# Fn::Sub conserva expresiones de shell literales y resuelve los valores del stack.
cloud_init = cloud_init.replace("${", "${!").replace("__REGION_APP__", "${AWS::Region}")
cloud_init = cloud_init.replace("__URL_APP__", f"s3://{bucket}/{clave}")

for rol in ("cliente", "backend"):
    contenido = cloud_init.replace("__ROL__", rol)
    if rol == "backend":
        contenido = contenido.replace("__ORIGEN_CLIENTE__", "http://${Cliente.PublicIp}")
    marcador = " " * 10 + f"__CLOUD_INIT_{rol.upper()}__"
    if plantilla.count(marcador) != 1:
        raise SystemExit(f"Marcador de User Data ausente o duplicado para {rol}.")
    plantilla = plantilla.replace(marcador, indent(contenido.rstrip(), " " * 10))

for marcador, valor in (
    ("__SSH_CIDR__", ssh_cidr),
    ("__BUCKET_APP__", bucket),
    ("__CLAVE_APP__", clave),
):
    plantilla = plantilla.replace(marcador, valor)

Path(destino).write_text(plantilla, encoding="utf-8")
PYTHON

mv -- "$temporal/template.yaml" .asistencia/template.yaml
printf 'Plantilla preparada en .asistencia/template.yaml. Región %s, bucket %s.\n' "$region" "$bucket"
