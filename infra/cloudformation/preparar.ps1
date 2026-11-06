#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/Preparacion.ps1')

function Read-AsistenciaYaml {
    param([string] $Ruta)
    return [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Ruta).Path).Replace("`r`n", "`n")
}

function Add-AsistenciaIndent {
    param([string] $Texto, [int] $Espacios)
    return [regex]::Replace($Texto.TrimEnd(), '(?m)^(?=\S|[^\S\r\n]+\S)', (' ' * $Espacios))
}

function Replace-AsistenciaMarcador {
    param([string] $Texto, [string] $Marcador, [string] $Contenido)
    if ([regex]::Matches($Texto, [regex]::Escape($Marcador)).Count -ne 1) {
        throw "Marcador ausente o duplicado en la plantilla: $Marcador"
    }
    return $Texto.Replace($Marcador, $Contenido)
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $cfg = Initialize-AsistenciaAws cfn $env:CFN_ASISTENCIA_REGION $env:CFN_ASISTENCIA_BUCKET $env:CFN_ASISTENCIA_SSH_CIDR
    $local = Join-Path $PSScriptRoot '.asistencia'
    $null = New-Item -ItemType Directory -Path $local -Force
    $temporal = New-Item -ItemType Directory -Path (Join-Path $local ([guid]::NewGuid().ToString()))
    try {
        $paquete = Join-Path $temporal.FullName 'app.tar.gz'
        New-AsistenciaPaquete $cfg.Tar (Join-Path $PSScriptRoot '../../app') $paquete
        $huella = (Get-FileHash -LiteralPath $paquete -Algorithm SHA256).Hash.ToLowerInvariant()
        $clave = "cloud-init-2/cloudformation/app/$huella.tar.gz"
        $uri = "s3://$($cfg.Bucket)/$clave"

        $plantilla = Read-AsistenciaYaml 'template.yaml'
        foreach ($archivo in @('red.yaml', 'computo.yaml')) {
            $recursos = Add-AsistenciaIndent (Read-AsistenciaYaml $archivo) 2
            $plantilla = Replace-AsistenciaMarcador $plantilla "  # @$archivo" $recursos
        }

        $cloudInit = (Read-AsistenciaYaml '../cloud-init.yaml').Replace('${', '${!').
            Replace('__REGION_APP__', '${AWS::Region}').Replace('__URL_APP__', $uri)
        foreach ($rol in @('cliente', 'backend')) {
            $contenido = $cloudInit.Replace('__ROL__', $rol)
            if ($rol -eq 'backend') {
                $contenido = $contenido.Replace('__ORIGEN_CLIENTE__', 'http://${Cliente.PublicIp}')
            }
            $marcador = (' ' * 10) + '__CLOUD_INIT_' + $rol.ToUpperInvariant() + '__'
            $plantilla = Replace-AsistenciaMarcador $plantilla $marcador (Add-AsistenciaIndent $contenido 10)
        }
        $plantilla = $plantilla.Replace('__SSH_CIDR__', $cfg.SshCidr).
            Replace('__BUCKET_APP__', $cfg.Bucket).Replace('__CLAVE_APP__', $clave)

        $objeto = Invoke-AsistenciaNative aws @('s3api', 'head-object', '--bucket', $cfg.Bucket,
            '--key', $clave, '--region', $cfg.Region, '--expected-bucket-owner', $cfg.Cuenta, '--no-cli-pager') -PermitirError
        if ($objeto.Codigo -ne 0) {
            $null = Invoke-AsistenciaNative aws @('s3', 'cp', $paquete, $uri, '--region', $cfg.Region,
                '--sse', 'AES256', '--content-type', 'application/gzip', '--only-show-errors', '--no-cli-pager')
        }

        [IO.File]::WriteAllText((Join-Path $local 'template.yaml'), $plantilla)
    } finally {
        Remove-Item -LiteralPath $temporal.FullName -Recurse -Force
    }
    Write-Host "Plantilla preparada en .asistencia/template.yaml. Región $($cfg.Region), bucket $($cfg.Bucket)."
} finally {
    Pop-Location
}
