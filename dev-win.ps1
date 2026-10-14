#Requires -Version 5.1
# Ejecutar con Windows PowerShell 5.1 o PowerShell 7 y Docker Desktop.
param(
    [ValidateSet('start', 'stop', 'logs', 'status')]
    [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$startupStarted = $false
$originalUid = $env:DEV_UID
$originalGid = $env:DEV_GID
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Docker fallo (codigo $LASTEXITCODE): docker $($args -join ' ')"
    }
}

function Invoke-Compose {
    Invoke-Docker compose --env-file .dev/compose.env -f docker-compose.dev.yml @args
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText((Join-Path $PWD.Path $Path), $Content, $utf8)
}

Push-Location $PSScriptRoot
try {
    if (-not (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Instala Docker Desktop con Docker Compose.'
    }
    Invoke-Docker compose version
    $dockerOs = Invoke-Docker info --format '{{.OSType}}'
    if (($dockerOs -join '').Trim() -ne 'linux') {
        throw 'Inicia Docker Desktop y selecciona contenedores Linux.'
    }

    if ($Action -ne 'start') {
        if (-not (Test-Path .dev/compose.env -PathType Leaf)) {
            throw 'Primero ejecuta .\dev-win.ps1.'
        }
        switch ($Action) {
            'stop' { Invoke-Compose down }
            'logs' { Invoke-Compose logs --tail=100 -f }
            'status' { Invoke-Compose ps }
        }
        return
    }

    if (-not (Test-Path sembrar/composer.lock -PathType Leaf) -or
        -not (Test-Path sembrar/package-lock.json -PathType Leaf)) {
        throw 'Clona primero sembrar dentro de esta carpeta: git clone git@github.com:CostanzoPablo/sembrar.git'
    }

    # Windows no tiene UID/GID Unix. Usar root dentro de los contenedores
    # permite escribir en los montajes de Docker Desktop sin ejecutar chown.
    $env:DEV_UID = '0'
    $env:DEV_GID = '0'

    foreach ($directory in @(
        '.dev/mysql', '.dev/composer-cache', '.dev/npm-cache',
        'sembrar/var', 'sembrar/vendor', 'sembrar/node_modules',
        'sembrar/public/build', 'sembrar/public/bundles', 'sembrar/public/uploads'
    )) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $composeEnv = ''
    if (Test-Path .dev/compose.env -PathType Leaf) {
        $composeEnv = [System.IO.File]::ReadAllText((Join-Path $PWD.Path '.dev/compose.env'))
    }
    $composeEnv = $composeEnv.Replace("`r`n", "`n")
    foreach ($name in @('DEV_UID', 'DEV_GID')) {
        $pattern = "(?m)^$name=.*$"
        if ([regex]::IsMatch($composeEnv, $pattern)) {
            $composeEnv = [regex]::Replace($composeEnv, $pattern, "$name=0")
        } else {
            $composeEnv = $composeEnv.TrimEnd() + "`n$name=0`n"
        }
    }
    if (-not [regex]::IsMatch($composeEnv, '(?m)^DEV_PORT=')) {
        $port = '8002'
        if ($env:DEV_PORT) { $port = $env:DEV_PORT }
        $composeEnv = $composeEnv.TrimEnd() + "`nDEV_PORT=$port`n"
    }
    Write-Utf8File '.dev/compose.env' ($composeEnv.Trim() + "`n")

    # Nunca copiar .env.bck: contiene configuracion ajena al entorno local.
    if (-not (Test-Path sembrar/.env -PathType Leaf)) {
        Write-Utf8File 'sembrar/.env' "APP_ENV=dev`nAPP_DEBUG=1`n"
    }

    $startupStarted = $true
    Write-Host "`nPreparando PHP y MySQL..."
    Invoke-Compose config --quiet
    Invoke-Compose build php
    Invoke-Compose up -d --wait --wait-timeout 180 mysql
    Invoke-Compose stop nginx php node

    Write-Host "`nInstalando dependencias PHP y preparando la base local..."
    Invoke-Compose run --rm --no-deps php composer install --no-interaction --prefer-dist
    Invoke-Compose run --rm --no-deps php composer check-platform-reqs
    # Esquema actual para una base exclusivamente local; no importa el backup.
    Invoke-Compose run --rm --no-deps php php bin/console doctrine:schema:update --force --no-interaction
    Invoke-Compose run --rm --no-deps php php /opt/sembrar/init-dev.php
    Invoke-Compose run --rm --no-deps php php bin/console assets:install public

    Write-Host "`nInstalando y compilando assets..."
    Invoke-Compose run --rm --no-deps node npm ci --no-audit --no-fund
    Invoke-Compose run --rm --no-deps node npm run dev

    Write-Host "`nIniciando la aplicacion y el recompilador de assets..."
    Invoke-Compose up -d --wait --wait-timeout 120
    # Enviar PHP por stdin evita las diferencias de comillas entre PowerShell
    # 5.1 y 7 al pasar argumentos a programas nativos de Windows.
    $httpCheck = @'
<?php
$context = stream_context_create(["http" => ["timeout" => 15]]);
$body = @file_get_contents("http://nginx/", false, $context);
if ($body === false) { fwrite(STDERR, "La aplicacion no responde correctamente.\n"); exit(1); }
'@
    $httpCheck | & docker compose --env-file .dev/compose.env -f docker-compose.dev.yml exec -T php php
    if ($LASTEXITCODE -ne 0) {
        throw 'La aplicacion no responde correctamente.'
    }
    Invoke-Compose ps

    $effectivePort = [regex]::Match($composeEnv, '(?m)^DEV_PORT=([^\r\n]*)').Groups[1].Value
    if ($env:DEV_PORT) { $effectivePort = $env:DEV_PORT }
    $adminEmail = 'admin@sembrar.local'
    $adminPassword = 'sembrar-dev'
    if ($env:DEV_ADMIN_EMAIL) { $adminEmail = $env:DEV_ADMIN_EMAIL }
    if ($env:DEV_ADMIN_PASSWORD) { $adminPassword = $env:DEV_ADMIN_PASSWORD }
    Write-Host "`nProyecto listo: http://localhost:$effectivePort"
    Write-Host "Usuario local: $adminEmail"
    Write-Host "Contrasena inicial: $adminPassword (si el usuario ya existia, conserva la anterior)"
    Write-Host 'Para detener: .\dev-win.ps1 stop'
} catch {
    [Console]::Error.WriteLine("`nError: $($_.Exception.Message)")
    if ($startupStarted) {
        [Console]::Error.WriteLine('No se pudo completar el inicio. Revisa la salida anterior.')
        try { Invoke-Compose logs --tail=40 mysql php nginx node } catch { }
        [Console]::Error.WriteLine('Puedes volver a ejecutar .\dev-win.ps1; los datos locales se conservan.')
    }
    exit 1
} finally {
    $env:DEV_UID = $originalUid
    $env:DEV_GID = $originalGid
    Pop-Location
}
