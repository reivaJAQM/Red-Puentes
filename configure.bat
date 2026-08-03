<# :
@echo off
title Tailscale Bridge Network - Configuración Inicial
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
pause
exit /b
#>

Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

Clear-Host
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "   🛠️  CONFIGURADOR DE RED DE PUENTES TAILSCALE (UNIVERSAL)" -ForegroundColor Cyan
Write-Host "   Personaliza el nombre de tu red, clave de autenticación y portal." -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Get-Location
if ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$configFile = Join-Path $scriptDir "network-config.json"
$authFile = Join-Path $scriptDir "authkey.txt"
$guideFile = Join-Path $scriptDir "INSTRUCCIONES_CLIENTE.txt"

# Cargar config actual si existe
$currName = "Red de Puentes Tailscale"
$currOrg = "Mi Organización"
$currInterval = 30
$currPortal = ""

if (Test-Path $configFile) {
    try {
        $json = Get-Content $configFile | ConvertFrom-Json
        if ($json.network_name) { $currName = $json.network_name }
        if ($json.organization) { $currOrg = $json.organization }
        if ($json.check_interval_seconds) { $currInterval = [int]$json.check_interval_seconds }
        if ($json.portal_url) { $currPortal = $json.portal_url }
    } catch {}
}

Write-Host "1. Nombre de tu Red de Puentes" -ForegroundColor Yellow
Write-Host "   (Ejemplo: Red Privada MiEmpresa, Red VPN Casa, Red de Puentes Personal)" -ForegroundColor DarkGray
$inputName = Read-Host "   Nombre [$currName]"
if (-not $inputName) { $inputName = $currName }

Write-Host ""
Write-Host "2. Nombre de tu Organización / Institución" -ForegroundColor Yellow
$inputOrg = Read-Host "   Organización [$currOrg]"
if (-not $inputOrg) { $inputOrg = $currOrg }

Write-Host ""
Write-Host "3. Clave de Autenticación de Tailscale (Auth Key)" -ForegroundColor Yellow
Write-Host "   Obtén una clave reutilizable desde: https://login.tailscale.com/admin/settings/keys" -ForegroundColor DarkGray
$currAuth = ""
if (Test-Path $authFile) {
    $currAuth = (Get-Content $authFile | Where-Object { $_ -match "\S" -and $_ -notmatch "^\s*#" } | Select-Object -First 1)
}

if ($currAuth) {
    Write-Host "   ✔ Clave detectada actualmente: $($currAuth.Substring(0, [Math]::Min(15, $currAuth.Length)))..." -ForegroundColor Green
    $inputAuth = Read-Host "   ¿Deseas reemplazarla? (Ingresa nueva clave o presiona ENTER para mantener)"
    if (-not $inputAuth) { $inputAuth = $currAuth }
} else {
    $inputAuth = Read-Host "   Pegar Auth Key (deja en blanco para configurar después)"
}

Write-Host ""
Write-Host "4. URL de Inicio / Portal de Destino (Opcional)" -ForegroundColor Yellow
Write-Host "   (Ej: https://portal.ejemplo.com/login o deja en blanco si no aplica)" -ForegroundColor DarkGray
$inputPortal = Read-Host "   URL del Portal [$currPortal]"
if (-not $inputPortal) { $inputPortal = $currPortal }

Write-Host ""
Write-Host "5. Intervalo de comprobación de failover (segundos)" -ForegroundColor Yellow
$inputIntervalStr = Read-Host "   Segundos [$currInterval]"
$inputInterval = $currInterval
if ($inputIntervalStr -and [int]::TryParse($inputIntervalStr, [ref]$inputInterval)) {}

# Crear JSON de configuración
$configObj = [PSCustomObject]@{
    network_name           = $inputName
    organization           = $inputOrg
    check_interval_seconds = $inputInterval
    portal_url             = $inputPortal
    custom_banner          = $true
}

$configObj | ConvertTo-Json | Set-Content $configFile -Encoding UTF8

# Guardar authkey.txt si existe clave
if ($inputAuth) {
    "# Auth Key para $inputName ($inputOrg)" | Set-Content $authFile -Encoding UTF8
    $inputAuth | Add-Content $authFile -Encoding UTF8
}

# Generar INSTRUCCIONES_CLIENTE.txt
$guideContent = @"
==============================================================================
  GUÍA FÁCIL: CÓMO CONECTARSE A LA $inputName
==============================================================================

¡Hola! Este programa te permite conectarte a Internet de forma segura a través 
de la red de puentes de $inputOrg.

No necesitas instalar nada previamente ni configurar nada difícil. Todo el 
proceso es automático.

------------------------------------------------------------------------------
PASOS PARA USAR EL PROGRAMA (WINDOWS)
------------------------------------------------------------------------------

1. BUSCA EL ARCHIVO:
   En tu computadora, ubica el archivo llamado "setup-client.bat".

2. DALE DOBLE CLIC:
   Haz doble clic sobre el archivo "setup-client.bat".

3. PERMISOS DE ADMINISTRADOR:
   Si Windows te muestra un mensaje preguntando "¿Quieres permitir que esta 
   aplicación haga cambios en el dispositivo?", haz clic en "SÍ".

4. ESPERA UNOS SEGUNDOS:
   Se abrirá una pantalla. El programa trabajará solo durante unos 
   segundos conectándote a la red.

5. ¡LISTO! YA ESTÁS CONECTADO:
   Cuando veas un recuadro VERDE en la pantalla que dice:
   "✔ CONECTADO EXITOSAMENTE AL PUENTE"
   significa que ya estás conectado y tu tráfico está navegando a través 
   del puente activo.
"@

if ($inputPortal) {
    $guideContent += @"


6. ACCEDER AL PORTAL DE INICIO:
   Una vez que la conexión sea exitosa, puedes ingresar al portal:
   👉 $inputPortal
"@
}

$guideContent += @"


------------------------------------------------------------------------------
¿CÓMO DESCONECTARSE CUANDO TERMINES?
------------------------------------------------------------------------------

Mientras necesites la conexión, DEJA LA VENTANA ABIERTA.

Cuando quieras desconectarte y volver a tu Internet normal de siempre, tienes 
dos opciones muy fáciles:

• OPCIÓN A: Presiona la tecla "Q" en tu teclado dentro de la ventana.
• OPCIÓN B: Simplemente cierra la ventana haciendo clic en la "X" arriba a la derecha.

Al cerrar la ventana, el programa te desconectará automáticamente y tu computadora 
volverá a su Internet habitual.

==============================================================================
Nota para usuarios de Mac:
Si estás usando una computadora Apple (Mac), el procedimiento es idéntico pero 
usando el archivo llamado "setup-client.command".
==============================================================================
"@

$guideContent | Set-Content $guideFile -Encoding UTF8

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "✔ CONFIGURACIÓN GUARDADA CON ÉXITO" -ForegroundColor Green
Write-Host "  Red         : $inputName" -ForegroundColor White
Write-Host "  Organización: $inputOrg" -ForegroundColor White
Write-Host "  Config      : network-config.json" -ForegroundColor Gray
Write-Host "  Auth Key    : authkey.txt" -ForegroundColor Gray
Write-Host "  Guía        : INSTRUCCIONES_CLIENTE.txt" -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host ""
