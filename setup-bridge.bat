<# :
@echo off
title Tailscale Bridge - Configurar Puente
cd /d "%~dp0"

REM Auto-elevar permisos de Administrador si es necesario
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
pause
exit /b
#>

#Requires -RunAsAdministrator
param(
    [string]$AuthKey = ""
)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

$ErrorActionPreference = "Stop"

$scriptDir = Get-Location
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$configFile = Join-Path $scriptDir "network-config.json"
$authFile = Join-Path $scriptDir "authkey.txt"

$networkName = "Red de Puentes Tailscale"
if (Test-Path $configFile) {
    try {
        $json = Get-Content $configFile | ConvertFrom-Json
        if ($json.network_name) { $networkName = $json.network_name }
    } catch {}
}

Clear-Host
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "   🌐 TAILSCALE BRIDGE SETUP  |  Configuración de Nodo Puente" -ForegroundColor Cyan
Write-Host "   Red: $networkName" -ForegroundColor Yellow
Write-Host "   Activación de Exit Node e IP Forwarding en Windows" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Verificar/instalar Tailscale ---
$tailscaleExe = Get-Command "tailscale" -ErrorAction SilentlyContinue
if (-not $tailscaleExe) {
    Write-Host "[!] Tailscale no instalado. Descargando instalador oficial..." -ForegroundColor Yellow
    $url = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
    $installer = "$env:TEMP\tailscale-setup.exe"
    Invoke-WebRequest -Uri $url -OutFile $installer
    Write-Host "[+] Instalando Tailscale en segundo plano..." -ForegroundColor Cyan
    Start-Process -Wait -FilePath $installer -ArgumentList "/S"
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
Write-Host "[✔] Tailscale verificado en el sistema." -ForegroundColor Green

# --- 2. Leer o solicitar Auth Key ---
$status = & "tailscale" status --json 2>$null | ConvertFrom-Json
$needAuth = (-not $status) -or ($status.BackendState -ne "Running") -or ($status.AuthURL -and $status.AuthURL.Trim() -ne "") -or ($status.Health -contains "You are logged out.")

if ($needAuth) {
    if ($AuthKey -eq "" -and (Test-Path $authFile)) {
        $AuthKey = (Get-Content $authFile | Where-Object { $_ -match "\S" -and $_ -notmatch "^\s*#" } | Select-Object -First 1)
        if ($AuthKey) { $AuthKey = $AuthKey.Trim() }
    }

    if ($AuthKey -eq "") {
        Write-Host ""
        Write-Host "[!] No se encontró ninguna Auth Key en authkey.txt." -ForegroundColor Yellow
        Write-Host "    Para vincular este puente automáticamente a tu red, necesitas una Auth Key." -ForegroundColor DarkGray
        Write-Host "    Genera una en: https://login.tailscale.com/admin/settings/keys" -ForegroundColor DarkGray
        $AuthKey = Read-Host "    Ingresa tu Auth Key de Tailscale"
    }

    if ($AuthKey -ne "") {
        Write-Host "[+] Autenticando nodo puente con Auth Key..." -ForegroundColor Yellow
        & "tailscale" up --authkey="$AuthKey" --accept-routes --advertise-exit-node --unattended --reset --force-reauth
    }

    $status = & "tailscale" status --json 2>$null | ConvertFrom-Json
    if (-not $status -or $status.BackendState -ne "Running" -or ($status.AuthURL -and $status.AuthURL.Trim() -ne "")) {
        Write-Host "[✘] Error de Autenticación. Revisa tu clave en https://login.tailscale.com/admin/settings/keys" -ForegroundColor Red
        Write-Host "    O guarda tu Auth Key en authkey.txt" -ForegroundColor DarkGray
        exit 2
    }
}
Write-Host "[✔] Sesión autenticada en el Tailnet." -ForegroundColor Green

# --- 3. Activar como exit node y modo unattended ---
Write-Host "[+] Configurando esta PC como Exit Node (puente)..." -ForegroundColor Cyan
& "tailscale" set --advertise-exit-node --unattended

# --- 4. Habilitar IP forwarding en Windows ---
$current = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -ErrorAction SilentlyContinue
if ($current.IPEnableRouter -ne 1) {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1
    Write-Host "[+] IP forwarding activado en el Registro de Windows (sugerido reiniciar si es primera vez)." -ForegroundColor Yellow
}

# --- 4b. Configurar energía (Desactivar Suspensión e Hibernación) ---
Write-Host "[+] Ajustando energía: Desactivando suspensión e hibernación..." -ForegroundColor Cyan
try {
    powercfg /change standby-timeout-ac 0 2>$null
    powercfg /change monitor-timeout-ac 0 2>$null
    powercfg /change disk-timeout-ac 0 2>$null
    powercfg /hibernate off 2>$null
    Write-Host "[✔] La PC no se suspenderá ni hibernará por inactividad." -ForegroundColor Green
} catch {
    Write-Host "[!] No se pudo ajustar powercfg." -ForegroundColor Yellow
}

# --- 5. Confirmación final ---
$bridgeIP = & "tailscale" ip -4
Write-Host ""
Write-Host "┌──────────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│ ✔ PUENTE CONFIGURADO CON ÉXITO                                           │" -ForegroundColor Green
Write-Host "│   Red         : $networkName                                             │" -ForegroundColor White
Write-Host "│   Nodo        : $(hostname)                                              │" -ForegroundColor White
Write-Host "│   IP Tailscale: $bridgeIP                                                │" -ForegroundColor White
Write-Host "│   Estado      : Exit Node silencioso (Unattended)                        │" -ForegroundColor Gray
Write-Host "└──────────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""
Write-Host "Si es la primera vez que agregas este nodo, apruébalo desde el panel:" -ForegroundColor Yellow
Write-Host "👉 https://login.tailscale.com/admin/machines" -ForegroundColor Cyan
Write-Host ""
