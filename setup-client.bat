<# :
@echo off
title Tailscale Bridge Network - Cliente
cd /d "%~dp0"

REM Auto-elevar permisos de Administrador si es necesario
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ==============================================================================
    echo [!] Ocurrio un error al ejecutar el cliente de Tailscale.
    echo ==============================================================================
    pause
)
exit /b
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Get-Location
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$CONFIG_FILE = Join-Path $SCRIPT_DIR "network-config.json"
$BRIDGES_FILE = Join-Path $SCRIPT_DIR "bridges.txt"
$AUTHKEY_FILE = Join-Path $SCRIPT_DIR "authkey.txt"

# Leer configuración dinámica
$NETWORK_NAME = "Red de Puentes Tailscale"
$CHECK_INTERVAL = 30
$PORTAL_URL = ""

if (Test-Path $CONFIG_FILE) {
    try {
        $jsonConfig = Get-Content $CONFIG_FILE | ConvertFrom-Json
        if ($jsonConfig.network_name) { $NETWORK_NAME = $jsonConfig.network_name }
        if ($jsonConfig.check_interval_seconds) { $CHECK_INTERVAL = [int]$jsonConfig.check_interval_seconds }
        if ($jsonConfig.portal_url) { $PORTAL_URL = $jsonConfig.portal_url }
    } catch {}
}

# --- Banner y Estilo ---
Clear-Host
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "   🌐 TAILSCALE BRIDGE CLIENT  |  $NETWORK_NAME" -ForegroundColor Cyan
Write-Host "   Enrutamiento Inteligente con Failover Automático y Alta Disponibilidad" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# --- Funciones ---
function Get-TailscalePath {
    $paths = @(
        "${env:ProgramFiles}\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-Tailscale {
    Write-Host "[!] Tailscale no está instalado. Descargando instalador oficial..." -ForegroundColor Yellow
    $url = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
    $installer = "$env:TEMP\tailscale-setup.exe"
    Invoke-WebRequest -Uri $url -OutFile $installer
    Write-Host "[+] Instalando Tailscale en segundo plano..." -ForegroundColor Cyan
    Start-Process -Wait -FilePath $installer -ArgumentList "/S"
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-Bridges {
    if (-not (Test-Path $BRIDGES_FILE)) {
        return @()
    }
    $bridges = Get-Content $BRIDGES_FILE | Where-Object {
        $_ -match "\S" -and $_ -notmatch "^\s*#"
    } | ForEach-Object { $_.Trim() }
    return $bridges
}

function Test-BridgeAlive($name) {
    try {
        return (Test-Connection -ComputerName $name -Count 1 -Quiet -ErrorAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Set-ExitNode($name) {
    Write-Host "[+]  Estableciendo salida de red a través de: $name" -ForegroundColor Green
    & $script:TAILSCALE set --exit-node $name
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "┌──────────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│ ✔ CONECTADO EXITOSAMENTE AL PUENTE                                       │" -ForegroundColor Green
        Write-Host "│   Node Activo : $name                                                     │" -ForegroundColor White
        Write-Host "│   Estado      : Enrutando todo el tráfico de forma segura                │" -ForegroundColor Gray
        Write-Host "└──────────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
        Write-Host ""
        
        if ($PORTAL_URL) {
            Write-Host "[🌐] Abriendo portal de la red: $PORTAL_URL" -ForegroundColor Cyan
            Start-Process $PORTAL_URL
        }
        return $true
    }
    Write-Host "[✘] Error al conectar con el puente $name." -ForegroundColor Red
    return $false
}

# --- Inicio ---
try {
    # 1. Asegurar Tailscale instalado
    Write-Host "[1/3] Verificando servicio de Tailscale..." -ForegroundColor DarkGray
    $TAILSCALE = Get-TailscalePath
    if (-not $TAILSCALE) {
        Install-Tailscale
        $TAILSCALE = Get-TailscalePath
        if (-not $TAILSCALE) {
            Write-Host "[✘] Error al instalar Tailscale." -ForegroundColor Red
            exit 1
        }
        Write-Host "[✔] Tailscale instalado correctamente." -ForegroundColor Green
    } else {
        Write-Host "[✔] Tailscale detectado en: $TAILSCALE" -ForegroundColor Green
    }

    # 2. Autenticar / Reautenticar automáticamente en la red correcta
    Write-Host "[2/3] Verificando sesión y alcanzabilidad del Tailnet..." -ForegroundColor DarkGray
    $status = & $TAILSCALE status --json 2>$null | ConvertFrom-Json
    $needLogin = $false

    if (-not $status -or $status.BackendState -ne "Running" -or ($status.AuthURL -and $status.AuthURL.Trim() -ne "") -or ($status.Health -contains "You are logged out.")) {
        $needLogin = $true
    } else {
        $hasExitOption = $false
        if ($status.Peer) {
            foreach ($p in $status.Peer.PSObject.Properties) {
                if ($p.Value.ExitNodeOption -eq $true) {
                    $hasExitOption = $true
                    break
                }
            }
        }
        if (-not $hasExitOption) {
            $bridgeReachable = $false
            if (Test-Path $BRIDGES_FILE) {
                $bList = Get-Content $BRIDGES_FILE | Where-Object { $_ -match "\S" -and $_ -notmatch "^\s*#" }
                foreach ($b in $bList) {
                    if (Test-BridgeAlive $b.Trim()) {
                        $bridgeReachable = $true
                        break
                    }
                }
            }
            if (-not $bridgeReachable) {
                Write-Host "[!] Sesión activa en Tailscale pero no pertenece a la red de puentes." -ForegroundColor Yellow
                $needLogin = $true
            }
        }
    }

    if ($needLogin) {
        $authKey = ""
        if (Test-Path $AUTHKEY_FILE) {
            $authKey = (Get-Content $AUTHKEY_FILE | Where-Object { $_ -match "\S" -and $_ -notmatch "^\s*#" } | Select-Object -First 1)
            if ($authKey) { $authKey = $authKey.Trim() }
        }

        if (-not $authKey) {
            Write-Host ""
            Write-Host "[!] No se encontró ninguna Auth Key en authkey.txt." -ForegroundColor Yellow
            Write-Host "    Pide la Auth Key al administrador o entra a: https://login.tailscale.com/admin/settings/keys" -ForegroundColor DarkGray
            $authKey = Read-Host "    Ingresa la Auth Key de tu red"
        }

        if ($authKey) {
            Write-Host "[+] Conectando a la red de puentes con Auth Key (--reset --force-reauth)..." -ForegroundColor Yellow
            & $TAILSCALE up --authkey $authKey --reset --force-reauth
            Start-Sleep -Seconds 2
            $statusCheck = & $TAILSCALE status --json 2>$null | ConvertFrom-Json
            if (-not $statusCheck -or $statusCheck.BackendState -ne "Running") {
                Write-Host "[!] Reintentando autenticación tras reiniciar estado local..." -ForegroundColor Yellow
                & $TAILSCALE logout 2>$null
                Start-Sleep -Seconds 1
                & $TAILSCALE up --authkey $authKey --reset --force-reauth
                Start-Sleep -Seconds 2
            }
        }
        $status = & $TAILSCALE status --json 2>$null | ConvertFrom-Json
        if (-not $status -or $status.BackendState -ne "Running") {
            Write-Host "[✘] Error: No se pudo autenticar en Tailscale." -ForegroundColor Red
            Write-Host "    Verifica la Auth Key en authkey.txt" -ForegroundColor DarkGray
            exit 1
        }
    }
    Write-Host "[✔] Sesión activa y conectada en la red." -ForegroundColor Green

    # 3. Autodetectar puentes en el Tailnet y actualizar bridges.txt
    Write-Host "[3/3] Autodetectando puentes disponibles en la red..." -ForegroundColor DarkGray
    $detectedBridges = @()
    if ($status -and $status.Peer) {
        foreach ($p in $status.Peer.PSObject.Properties) {
            if ($p.Value.ExitNodeOption -eq $true) {
                $detectedBridges += $p.Value.HostName
            }
        }
    }

    if ($detectedBridges.Count -gt 0) {
        Set-Content $BRIDGES_FILE $detectedBridges
        Write-Host "[✔] Puentes autodetectados en vivo ($($detectedBridges.Count)): $($detectedBridges -join ', ')" -ForegroundColor Green
    }

    $bridges = Get-Bridges
    if ($bridges.Count -eq 0) {
        Write-Host "[✘] No se encontraron puentes activos en la red ni en bridges.txt." -ForegroundColor Red
        Write-Host "    Asegúrate de haber configurado e iniciado al menos un nodo puente (setup-bridge)." -ForegroundColor DarkGray
        exit 1
    }
    Write-Host "[✔] Puentes activos configurados ($($bridges.Count)): $($bridges -join ', ')" -ForegroundColor Green
    Write-Host ""

    Write-Host "  STATUS: CONEXIÓN ACTIVA  " -ForegroundColor Black -BackgroundColor Green -NoNewline
    Write-Host "  Monitoreo de failover en ejecución (cada $CHECK_INTERVAL s)" -ForegroundColor DarkGray
    Write-Host " Presiona [ Q ] o [ Ctrl+C ] en esta ventana para desconectarte y salir." -ForegroundColor Magenta
    Write-Host "------------------------------------------------------------------------------" -ForegroundColor DarkGray

    # 4. Loop de failover
    $currentNode = $null
    $exitRequested = $false

    while (-not $exitRequested) {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Q" -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                $exitRequested = $true
                break
            }
        }
        if ($exitRequested) { break }

        $aliveNode = $null
        $timestamp = Get-Date -Format "HH:mm:ss"

        foreach ($b in $bridges) {
            Write-Host "[$timestamp]  Probando disponibilidad de puente: $b" -ForegroundColor DarkGray
            if (Test-BridgeAlive $b) {
                $aliveNode = $b
                Write-Host "[$timestamp] ✔ Puente respondiendo: $b" -ForegroundColor Green
                break
            } else {
                Write-Host "[$timestamp] ✖ Puente sin respuesta: $b" -ForegroundColor Yellow
            }
        }

        if (-not $aliveNode) {
            Write-Host "[!]  Ningún puente disponible en este momento. Reintentando..." -ForegroundColor Red
        } elseif ($aliveNode -ne $currentNode) {
            if (Set-ExitNode $aliveNode) {
                $currentNode = $aliveNode
            }
        }

        # Esperar el intervalo escuchando la tecla 'Q' o 'q' cada 100ms para respuesta inmediata
        for ($i = 0; $i -lt ($CHECK_INTERVAL * 10); $i++) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Q" -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                    $exitRequested = $true
                    break
                }
            }
            Start-Sleep -Milliseconds 100
        }
    }
} finally {
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Yellow
    Write-Host "[+] Desconectando del puente de salida..." -ForegroundColor Yellow
    if ($TAILSCALE) {
        & $TAILSCALE set --exit-node="" 2>$null
    }
    Write-Host "[✔] Desconectado con éxito. Tu tráfico ha vuelto a tu red habitual." -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Yellow
}
