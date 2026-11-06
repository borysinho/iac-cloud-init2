#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export AWS_PAGER=""

region=${TF_VAR_region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}}
cuenta=$(aws sts get-caller-identity --region "$region" --query Account --output text)
bucket=${TOFU_STATE_BUCKET:-}
if [[ -z $bucket || $bucket == nombre-unico-del-bucket-de-estado ]]; then
  bucket="asistencia-cloud-init-2-tofu-$cuenta-$region"
fi
if [[ ! $cuenta =~ ^[0-9]{12}$ || ! $region =~ ^[a-z0-9-]+$ ||
      ! $bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  printf 'Revisa la cuenta, la región y el nombre del bucket.\n' >&2
  exit 1
fi

ssh_cidr=${TF_VAR_ssh_cidr:-}
ssh_cidr=${ssh_cidr#"${ssh_cidr%%[![:space:]]*}"}
ssh_cidr=${ssh_cidr%"${ssh_cidr##*[![:space:]]}"}
octeto='(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
ipv4="($octeto\\.){3}$octeto"

if [[ -z $ssh_cidr || $ssh_cidr == TU_IPV4_PUBLICA/32 ]]; then
  if ! ip_publica=$(curl -fsS -4 --max-time 15 https://checkip.amazonaws.com) ||
     [[ ! $ip_publica =~ ^[[:space:]]*($ipv4)[[:space:]]*$ ]]; then
    printf 'No se pudo detectar la IPv4 pública. Define TF_VAR_ssh_cidr con tu IPv4 pública y vuelve a ejecutar ./preparar.sh.\n' >&2
    exit 1
  fi
  ssh_cidr="${BASH_REMATCH[1]}/32"
elif [[ $ssh_cidr =~ ^$ipv4(/32)?$ ]]; then
  ssh_cidr="${ssh_cidr%/32}/32"
else
  printf 'TF_VAR_ssh_cidr debe ser una IPv4 pública, con o sin /32. Ejecuta unset TF_VAR_ssh_cidr para detectarla automáticamente.\n' >&2
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

perfil_aws=${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}
backend_auth=
if aws configure get login_session --profile "$perfil_aws" >/dev/null 2>&1; then
  if [[ ! $perfil_aws =~ ^[a-zA-Z0-9_+=,.@-]+$ ]]; then
    printf 'El nombre del perfil AWS contiene caracteres incompatibles con el preparador.\n' >&2
    exit 1
  fi

  # AWS CLI entrega credenciales temporales a OpenTofu cuando las solicita.
  cat > "$temporal/aws-config" <<CONFIG
[profile asistencia-opentofu-cli]
region = $region
credential_process = aws configure export-credentials --profile $perfil_aws --format process
CONFIG

  backend_auth='
    profile             = "asistencia-opentofu-cli"
    shared_config_files = [".asistencia/aws-config"]'
fi

cat > "$temporal/backend_override.tf" <<CONFIG
terraform {
  backend "s3" {
    bucket              = "$bucket"
    region              = "$region"
    key                 = "cloud-init-2/opentofu/terraform.tfstate"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["$cuenta"]$backend_auth
  }
}
CONFIG

if [[ -n $backend_auth ]]; then
  cat >> "$temporal/backend_override.tf" <<'CONFIG'

provider "aws" {
  profile             = "asistencia-opentofu-cli"
  shared_config_files = [".asistencia/aws-config"]
}
CONFIG
  mv -- "$temporal/aws-config" .asistencia/aws-config
fi

cat > "$temporal/asistencia.auto.tfvars" <<CONFIG
region       = "$region"
state_bucket = "$bucket"
aws_account  = "$cuenta"
ssh_cidr     = "$ssh_cidr"
CONFIG

mv -- "$temporal/app.tar.gz" .asistencia/app.tar.gz
mv -- "$temporal/backend_override.tf" backend_override.tf
mv -- "$temporal/asistencia.auto.tfvars" asistencia.auto.tfvars
printf 'Preparación completa. Bucket %s y acceso SSH desde %s.\n' "$bucket" "$ssh_cidr"
