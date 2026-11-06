#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/Preparacion.ps1')

Push-Location -LiteralPath $PSScriptRoot
try {
    $cfg = Initialize-AsistenciaAws tofu $env:TF_VAR_region $env:TOFU_STATE_BUCKET $env:TF_VAR_ssh_cidr
    $local = Join-Path $PSScriptRoot '.asistencia'
    $null = New-Item -ItemType Directory -Path $local -Force
    $temporal = New-Item -ItemType Directory -Path (Join-Path $local ([guid]::NewGuid().ToString()))
    try {
        $paquete = Join-Path $temporal.FullName 'app.tar.gz'
        New-AsistenciaPaquete $cfg.Tar (Join-Path $PSScriptRoot '../../app') $paquete

        $perfil = Get-AsistenciaAwsPerfil
        $backendAuth = ''
        $providerAuth = ''
        if ($perfil.UsaLogin) {
            New-AsistenciaPerfilTemporal $perfil 'asistencia-opentofu-cli' $cfg.Region $local
            $backendAuth = @'

    profile             = "asistencia-opentofu-cli"
    shared_config_files = [".asistencia/aws-config"]
'@
            $providerAuth = @'


provider "aws" {
  profile             = "asistencia-opentofu-cli"
  shared_config_files = [".asistencia/aws-config"]
}
'@
        }

        @"
terraform {
  backend "s3" {
    bucket              = "$($cfg.Bucket)"
    region              = "$($cfg.Region)"
    key                 = "cloud-init-2/opentofu/terraform.tfstate"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["$($cfg.Cuenta)"]$backendAuth
  }
}$providerAuth
"@ | Set-Content -LiteralPath 'backend_override.tf' -Encoding utf8NoBOM

        @"
region       = "$($cfg.Region)"
state_bucket = "$($cfg.Bucket)"
aws_account  = "$($cfg.Cuenta)"
ssh_cidr     = "$($cfg.SshCidr)"
"@ | Set-Content -LiteralPath 'asistencia.auto.tfvars' -Encoding utf8NoBOM

        Move-Item -LiteralPath $paquete -Destination (Join-Path $local 'app.tar.gz') -Force
    } finally {
        Remove-Item -LiteralPath $temporal.FullName -Recurse -Force
    }
    Write-Host "Preparación completa. Bucket $($cfg.Bucket) y acceso SSH desde $($cfg.SshCidr)."
} finally {
    Pop-Location
}
