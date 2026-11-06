#Requires -Version 7.4

function Invoke-AsistenciaNative {
    param(
        [string] $Programa,
        [string[]] $Argumentos,
        [switch] $PermitirError
    )

    $PSNativeCommandUseErrorActionPreference = $false
    $salida = & $Programa @Argumentos 2>&1
    $resultado = [pscustomobject]@{
        Codigo = $LASTEXITCODE
        Texto = ($salida -join "`n").Trim()
    }
    if ($resultado.Codigo -ne 0 -and -not $PermitirError) {
        throw "$Programa terminó con código $($resultado.Codigo). $($resultado.Texto)"
    }
    return $resultado
}

function Get-AsistenciaTar {
    $candidatos = @(Get-Command tar -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Source)

    if ($IsWindows) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($git) {
            $candidatos += Join-Path (Split-Path (Split-Path $git.Source)) 'usr/bin/tar.exe'
        }
        if ($env:ProgramFiles) {
            $candidatos += Join-Path $env:ProgramFiles 'Git/usr/bin/tar.exe'
        }
    }

    foreach ($candidato in ($candidatos | Select-Object -Unique)) {
        if ((Test-Path -LiteralPath $candidato -PathType Leaf) -and
            (Invoke-AsistenciaNative $candidato @('--version') -PermitirError).Texto -match 'GNU tar') {
            return $candidato
        }
    }
    throw 'Se necesita GNU tar. En Windows, instala Git for Windows o agrega GNU tar al PATH.'
}

function Initialize-AsistenciaAws {
    param(
        [string] $Herramienta,
        [string] $Region,
        [string] $Bucket,
        [string] $SshCidr
    )

    if (-not $Region) { $Region = $env:AWS_REGION ?? $env:AWS_DEFAULT_REGION ?? 'us-east-2' }
    if ($Region -notmatch '^[a-z0-9-]+$') { throw 'Indica una región válida de AWS.' }

    $tar = Get-AsistenciaTar
    $octeto = '(?:0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
    $ipv4 = "(?:$octeto\.){3}$octeto"
    $SshCidr = $SshCidr.Trim()
    if (-not $SshCidr -or $SshCidr -eq 'TU_IPV4_PUBLICA/32') {
        $curl = if ($IsWindows) { 'curl.exe' } else { 'curl' }
        $ip = (Invoke-AsistenciaNative $curl @('-fsS', '-4', '--max-time', '15', 'https://checkip.amazonaws.com')).Texto
        if ($ip -notmatch "^$ipv4$") { throw 'No se pudo detectar una IPv4 pública para SSH.' }
        $SshCidr = "$ip/32"
    } elseif ($SshCidr -match "^($ipv4)(?:/32)?$") {
        $SshCidr = "$($Matches[1])/32"
    } else {
        throw 'Indica una IPv4 pública con o sin /32.'
    }

    $cuenta = (Invoke-AsistenciaNative aws @('sts', 'get-caller-identity', '--region', $Region,
        '--query', 'Account', '--output', 'text', '--no-cli-pager')).Texto
    if ($cuenta -notmatch '^[0-9]{12}$') { throw 'AWS CLI no devolvió una cuenta válida.' }

    if (-not $Bucket -or $Bucket -eq 'nombre-unico-del-bucket-de-estado') {
        $Bucket = "asistencia-cloud-init-2-$Herramienta-$cuenta-$Region"
    }
    if ($Bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw 'Indica un nombre válido de bucket S3.' }

    $clave = Invoke-AsistenciaNative aws @('ec2', 'describe-key-pairs', '--region', $Region,
        '--key-names', 'globomatics', '--no-cli-pager') -PermitirError
    if ($clave.Codigo -ne 0) {
        if ($clave.Texto -notmatch 'InvalidKeyPair\.NotFound') { throw $clave.Texto }
        $publica = $env:GLOBOMATICS_PUBLIC_KEY ?? (Join-Path $HOME 'globomatics-ec2.pub')
        if (-not (Test-Path -LiteralPath $publica -PathType Leaf)) {
            throw 'Indica la ruta de la clave pública existente en GLOBOMATICS_PUBLIC_KEY.'
        }
        $publica = (Resolve-Path -LiteralPath $publica).Path
        $null = Invoke-AsistenciaNative aws @('ec2', 'import-key-pair', '--region', $Region,
            '--key-name', 'globomatics', '--public-key-material', "fileb://$publica", '--no-cli-pager')
    }

    $destino = @('--bucket', $Bucket, '--region', $Region, '--expected-bucket-owner', $cuenta, '--no-cli-pager')
    $acceso = Invoke-AsistenciaNative aws (@('s3api', 'head-bucket') + $destino) -PermitirError
    if ($acceso.Codigo -ne 0) {
        if ($acceso.Texto -notmatch '\(404\)|NoSuchBucket') { throw $acceso.Texto }
        $argumentos = @('s3api', 'create-bucket', '--bucket', $Bucket, '--region', $Region, '--no-cli-pager')
        if ($Region -ne 'us-east-1') { $argumentos += @('--create-bucket-configuration', "LocationConstraint=$Region") }
        $null = Invoke-AsistenciaNative aws $argumentos
    }

    $ubicacion = (Invoke-AsistenciaNative aws (@('s3api', 'get-bucket-location') + $destino +
        @('--query', 'LocationConstraint', '--output', 'text'))).Texto
    if ($ubicacion -eq 'None') { $ubicacion = 'us-east-1' }
    if ($ubicacion -eq 'EU') { $ubicacion = 'eu-west-1' }
    if ($ubicacion -ne $Region) { throw "El bucket $Bucket está en $ubicacion. Selecciona esa región u otro bucket." }

    $null = Invoke-AsistenciaNative aws (@('s3api', 'put-public-access-block') + $destino +
        @('--public-access-block-configuration', 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'))
    $null = Invoke-AsistenciaNative aws (@('s3api', 'put-bucket-versioning') + $destino +
        @('--versioning-configuration', 'Status=Enabled'))

    return @{ Cuenta = $cuenta; Region = $Region; Bucket = $Bucket; SshCidr = $SshCidr; Tar = $tar }
}

function New-AsistenciaPaquete {
    param([string] $Tar, [string] $App, [string] $Salida)
    $rutaAnterior = $env:PATH
    try {
        if ($IsWindows) {
            $env:PATH = (Split-Path $Tar) + ';' + $rutaAnterior
            $Salida = $Salida.Replace('\', '/')
            $App = $App.Replace('\', '/')
        }
        $null = Invoke-AsistenciaNative $Tar @('--force-local', '--sort=name', '--mtime=@0', '--owner=0',
            '--group=0', '--numeric-owner', '-czf', $Salida, '-C', $App,
            'package.json', 'package-lock.json', 'public', 'src', 'scripts', 'database')
    } finally {
        $env:PATH = $rutaAnterior
    }
}

function Get-AsistenciaAwsPerfil {
    $perfil = $env:AWS_PROFILE ?? $env:AWS_DEFAULT_PROFILE ?? 'default'
    $config = $env:AWS_CONFIG_FILE ?? (Join-Path $HOME '.aws/config')
    if ($perfil -eq 'asistencia-pulumi-cli' -and $env:ASISTENCIA_PULUMI_PERFIL_ORIGINAL -and
        $env:ASISTENCIA_PULUMI_CONFIG_ORIGINAL) {
        $perfil = $env:ASISTENCIA_PULUMI_PERFIL_ORIGINAL
        $config = $env:ASISTENCIA_PULUMI_CONFIG_ORIGINAL
    }

    $config = [IO.Path]::GetFullPath($config)
    $original = $env:AWS_CONFIG_FILE
    try {
        $env:AWS_CONFIG_FILE = $config
        $login = Invoke-AsistenciaNative aws @('configure', 'get', 'login_session', '--profile', $perfil) -PermitirError
    } finally {
        $env:AWS_CONFIG_FILE = $original
    }
    return @{ Nombre = $perfil; Config = $config; UsaLogin = ($login.Codigo -eq 0 -and $login.Texto) }
}

function New-AsistenciaPerfilTemporal {
    param([hashtable] $Perfil, [string] $Nombre, [string] $Region, [string] $Local)
    $config = $Perfil.Config.Replace('\', '/')
    if ($Perfil.Nombre -notmatch '^[a-zA-Z0-9_+=,.@-]+$' -or $config -match '["\r\n]') {
        throw 'Revisa el nombre del perfil AWS y la ruta de su archivo de configuración.'
    }

    $nombrePwsh = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $pwsh = (Join-Path $PSHOME $nombrePwsh).Replace('\', '/')
    $auxiliar = (Join-Path $Local 'credenciales.ps1').Replace('\', '/')
    @'
param([string] $Perfil, [string] $Configuracion)
$env:AWS_CONFIG_FILE = $Configuracion
aws configure export-credentials --profile $Perfil --format process
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $auxiliar -Encoding utf8NoBOM
    @"
[profile $Nombre]
region = $Region
credential_process = "$pwsh" -NoProfile -File "$auxiliar" -Perfil $($Perfil.Nombre) -Configuracion "$config"
"@ | Set-Content -LiteralPath (Join-Path $Local 'aws-config') -Encoding utf8NoBOM
}

function ConvertTo-AsistenciaPsLiteral {
    param([string] $Valor)
    return "'" + $Valor.Replace("'", "''") + "'"
}
