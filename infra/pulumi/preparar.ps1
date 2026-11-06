#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/Preparacion.ps1')

Push-Location -LiteralPath $PSScriptRoot
try {
    $cfg = Initialize-AsistenciaAws pulumi $env:PULUMI_ASISTENCIA_REGION $env:PULUMI_ASISTENCIA_BUCKET $env:PULUMI_ASISTENCIA_SSH_CIDR
    $local = Join-Path $PSScriptRoot '.asistencia'
    $null = New-Item -ItemType Directory -Path $local -Force
    $temporal = New-Item -ItemType Directory -Path (Join-Path $local ([guid]::NewGuid().ToString()))
    try {
        $paquete = Join-Path $temporal.FullName 'app.tar.gz'
        New-AsistenciaPaquete $cfg.Tar (Join-Path $PSScriptRoot '../../app') $paquete

        $npm = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
        $null = Invoke-AsistenciaNative $npm @('ci', '--no-audit', '--no-fund')

        $frase = $env:PULUMI_ASISTENCIA_PASSPHRASE_FILE ?? (Join-Path $local 'passphrase')
        if (-not (Test-Path -LiteralPath $frase -PathType Leaf) -or (Get-Item -LiteralPath $frase).Length -eq 0) {
            if ($env:PULUMI_ASISTENCIA_PASSPHRASE_FILE) {
                throw 'El archivo de frase de cifrado indicado no existe o está vacío.'
            }
            $bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
            $fraseTemporal = Join-Path $temporal.FullName 'passphrase'
            [Convert]::ToHexString($bytes).ToLowerInvariant() |
                Set-Content -LiteralPath $fraseTemporal -Encoding utf8NoBOM
            if ($IsWindows) {
                $identidad = [Security.Principal.WindowsIdentity]::GetCurrent().User
                $acl = Get-Acl -LiteralPath $fraseTemporal
                $acl.SetAccessRuleProtection($true, $false)
                $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                    $identidad, 'FullControl', 'Allow'))
                Set-Acl -LiteralPath $fraseTemporal -AclObject $acl
            } else {
                [IO.File]::SetUnixFileMode($fraseTemporal,
                    [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)
            }
            Move-Item -LiteralPath $fraseTemporal -Destination $frase -Force
        }
        $frase = (Resolve-Path -LiteralPath $frase).Path

        $variables = [ordered]@{
            PULUMI_BACKEND_URL = "s3://$($cfg.Bucket)/cloud-init-2/pulumi?region=$($cfg.Region)&awssdk=v2"
            PULUMI_CONFIG_PASSPHRASE_FILE = $frase
            AWS_REGION = $cfg.Region
        }

        $perfil = Get-AsistenciaAwsPerfil
        if ($perfil.UsaLogin) {
            New-AsistenciaPerfilTemporal $perfil 'asistencia-pulumi-cli' $cfg.Region $local
            $variables.ASISTENCIA_PULUMI_PERFIL_ORIGINAL = $perfil.Nombre
            $variables.ASISTENCIA_PULUMI_CONFIG_ORIGINAL = $perfil.Config
            $variables.AWS_PROFILE = 'asistencia-pulumi-cli'
            $variables.AWS_CONFIG_FILE = Join-Path $local 'aws-config'
        }
        $entorno = Join-Path $temporal.FullName 'entorno.ps1'
        $contenidoEntorno = foreach ($variable in $variables.GetEnumerator()) {
            '$env:' + $variable.Key + ' = ' + (ConvertTo-AsistenciaPsLiteral $variable.Value)
        }
        Set-Content -LiteralPath $entorno -Value $contenidoEntorno -Encoding utf8NoBOM

        $anteriores = @{}
        foreach ($nombre in $variables.Keys) {
            $anteriores[$nombre] = [Environment]::GetEnvironmentVariable($nombre, 'Process')
        }
        try {
            . $entorno
            $null = Invoke-AsistenciaNative pulumi @('stack', 'select', 'laboratorio', '--create', '--non-interactive')
            $null = Invoke-AsistenciaNative pulumi @('config', 'set-all', '--non-interactive',
                '--plaintext', "region=$($cfg.Region)", '--plaintext', "bucket=$($cfg.Bucket)",
                '--plaintext', "cuenta=$($cfg.Cuenta)", '--plaintext', "sshCidr=$($cfg.SshCidr)")
            Move-Item -LiteralPath $paquete -Destination (Join-Path $local 'app.tar.gz') -Force
            Move-Item -LiteralPath $entorno -Destination (Join-Path $local 'entorno.ps1') -Force
        } catch {
            foreach ($nombre in $anteriores.Keys) {
                [Environment]::SetEnvironmentVariable($nombre, $anteriores[$nombre], 'Process')
            }
            throw
        }
    } finally {
        Remove-Item -LiteralPath $temporal.FullName -Recurse -Force
    }
    Write-Host "Stack laboratorio preparado. Bucket $($cfg.Bucket) y acceso SSH desde $($cfg.SshCidr)."
} finally {
    Pop-Location
}
