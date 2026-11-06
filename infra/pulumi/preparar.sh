#!/usr/bin/env bash

# Cargar el entorno del proyecto en la terminal que ejecutará Pulumi.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  if bash "${BASH_SOURCE[0]}" --cargar-entorno; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/.asistencia/entorno.sh"
    return $?
  fi
  return 1
fi
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""
export PULUMI_SKIP_UPDATE_CHECK=true

perfil_aws=${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}
config_aws=${AWS_CONFIG_FILE:-"$HOME/.aws/config"}
if [[ $perfil_aws == asistencia-pulumi-cli && $config_aws == "$PWD/.asistencia/aws-config" ]]; then
  perfil_aws=${ASISTENCIA_PULUMI_PERFIL_ORIGINAL:?}
  config_aws=${ASISTENCIA_PULUMI_CONFIG_ORIGINAL:?}
  export AWS_PROFILE="$perfil_aws" AWS_CONFIG_FILE="$config_aws"
fi
config_aws=$(realpath -m -- "$config_aws")

region=${PULUMI_ASISTENCIA_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}}
cuenta=$(aws sts get-caller-identity --region "$region" --query Account --output text)
bucket=${PULUMI_ASISTENCIA_BUCKET:-}
if [[ -z $bucket || $bucket == nombre-unico-del-bucket-de-estado ]]; then
  bucket="asistencia-cloud-init-2-pulumi-$cuenta-$region"
fi
if [[ ! $cuenta =~ ^[0-9]{12}$ || ! $region =~ ^[a-z0-9-]+$ ||
      ! $bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  printf 'Revisa la cuenta, la región y el nombre del bucket.\n' >&2
  exit 1
fi

ssh_cidr=${PULUMI_ASISTENCIA_SSH_CIDR:-}
ssh_cidr=${ssh_cidr#"${ssh_cidr%%[![:space:]]*}"}
ssh_cidr=${ssh_cidr%"${ssh_cidr##*[![:space:]]}"}
octeto='(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
ipv4="($octeto\\.){3}$octeto"

if [[ -z $ssh_cidr || $ssh_cidr == TU_IPV4_PUBLICA/32 ]]; then
  if ! ip_publica=$(curl -fsS -4 --max-time 15 https://checkip.amazonaws.com) ||
     [[ ! $ip_publica =~ ^[[:space:]]*($ipv4)[[:space:]]*$ ]]; then
    printf 'No se pudo detectar la IPv4 pública. Define PULUMI_ASISTENCIA_SSH_CIDR con tu IPv4 pública y vuelve a ejecutar ./preparar.sh.\n' >&2
    exit 1
  fi
  ssh_cidr="${BASH_REMATCH[1]}/32"
elif [[ $ssh_cidr =~ ^$ipv4(/32)?$ ]]; then
  ssh_cidr="${ssh_cidr%/32}/32"
else
  printf 'PULUMI_ASISTENCIA_SSH_CIDR debe ser una IPv4 pública, con o sin /32. Ejecuta unset PULUMI_ASISTENCIA_SSH_CIDR para detectarla automáticamente.\n' >&2
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

npm ci --no-audit --no-fund

frase=${PULUMI_ASISTENCIA_PASSPHRASE_FILE:-"$PWD/.asistencia/passphrase"}
if [[ ! -s $frase ]]; then
  if [[ -n ${PULUMI_ASISTENCIA_PASSPHRASE_FILE:-} ]]; then
    printf 'El archivo de frase de cifrado indicado no existe o está vacío.\n' >&2
    exit 1
  fi
  (umask 077; openssl rand -hex 32 > "$temporal/passphrase")
  mv -- "$temporal/passphrase" "$frase"
fi
frase=$(realpath -- "$frase")

{
  printf 'export PULUMI_BACKEND_URL=%q\n' "s3://$bucket/cloud-init-2/pulumi?region=$region&awssdk=v2"
  printf 'export PULUMI_CONFIG_PASSPHRASE_FILE=%q\n' "$frase"
  printf 'export AWS_REGION=%q\n' "$region"
} > "$temporal/entorno.sh"

if aws configure get login_session --profile "$perfil_aws" >/dev/null 2>&1; then
  if [[ ! $perfil_aws =~ ^[a-zA-Z0-9_+=,.@-]+$ ||
        $config_aws == *'"'* || $config_aws == *'\'* || $config_aws == *$'\n'* ]]; then
    printf 'Revisa el nombre del perfil y la ruta del archivo de configuración AWS.\n' >&2
    exit 1
  fi
  cat > "$temporal/aws-config" <<CONFIG
[profile asistencia-pulumi-cli]
region = $region
credential_process = env "AWS_CONFIG_FILE=$config_aws" aws configure export-credentials --profile $perfil_aws --format process
CONFIG
  mv -- "$temporal/aws-config" .asistencia/aws-config

  {
    printf 'export ASISTENCIA_PULUMI_PERFIL_ORIGINAL=%q\n' "$perfil_aws"
    printf 'export ASISTENCIA_PULUMI_CONFIG_ORIGINAL=%q\n' "$config_aws"
    printf 'export AWS_PROFILE=%q\n' asistencia-pulumi-cli
    printf 'export AWS_CONFIG_FILE=%q\n' "$PWD/.asistencia/aws-config"
  } >> "$temporal/entorno.sh"
fi

source "$temporal/entorno.sh"
pulumi stack select laboratorio --create --non-interactive
pulumi config set-all --non-interactive \
  --plaintext "region=$region" \
  --plaintext "bucket=$bucket" \
  --plaintext "cuenta=$cuenta" \
  --plaintext "sshCidr=$ssh_cidr"

mv -- "$temporal/app.tar.gz" .asistencia/app.tar.gz
mv -- "$temporal/entorno.sh" .asistencia/entorno.sh
printf 'Stack laboratorio preparado. Bucket %s y acceso SSH desde %s.\n' "$bucket" "$ssh_cidr"
if [[ ${1:-} != --cargar-entorno ]]; then
  printf 'Antes de ejecutar Pulumi en esta terminal, carga el entorno con source ./.asistencia/entorno.sh.\n'
fi
