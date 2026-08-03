#!/bin/bash
# ==============================================================================
# 🛠️ TAILSCALE BRIDGE NETWORK - Asistente de Configuración Inicial (Mac/Linux)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/network-config.json"
AUTHKEY_FILE="$SCRIPT_DIR/authkey.txt"
GUIDE_FILE="$SCRIPT_DIR/INSTRUCCIONES_CLIENTE.txt"

BOLD="\033[1m"
RESET="\033[0m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
GRAY="\033[0;90m"

clear
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${BOLD}${CYAN}   🛠️  CONFIGURADOR DE RED DE PUENTES TAILSCALE (UNIVERSAL)${RESET}"
echo -e "${GRAY}   Personaliza el nombre de tu red, clave de autenticación y portal.${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo ""

# Leer valores actuales si existen
CURRENT_NAME="Red de Puentes Tailscale"
CURRENT_ORG="Mi Organización"
CURRENT_INTERVAL=30
CURRENT_PORTAL=""

if [[ -f "$CONFIG_FILE" ]] && command -v python3 &>/dev/null; then
    CURRENT_NAME=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('network_name', '$CURRENT_NAME'))" 2>/dev/null || echo "$CURRENT_NAME")
    CURRENT_ORG=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('organization', '$CURRENT_ORG'))" 2>/dev/null || echo "$CURRENT_ORG")
    CURRENT_INTERVAL=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('check_interval_seconds', 30))" 2>/dev/null || echo "30")
    CURRENT_PORTAL=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('portal_url', ''))" 2>/dev/null || echo "")
fi

echo -e "${BOLD}1. Nombre de tu Red de Puentes${RESET}"
echo -e "${GRAY}   (Ejemplo: Red Privada MiEmpresa, Red VPN Casa, Red de Puentes Personal)${RESET}"
read -p "   Nombre [$CURRENT_NAME]: " INPUT_NAME
NETWORK_NAME="${INPUT_NAME:-$CURRENT_NAME}"

echo ""
echo -e "${BOLD}2. Nombre de tu Organización / Institución${RESET}"
read -p "   Organización [$CURRENT_ORG]: " INPUT_ORG
ORG_NAME="${INPUT_ORG:-$CURRENT_ORG}"

echo ""
echo -e "${BOLD}3. Clave de Autenticación de Tailscale (Auth Key)${RESET}"
echo -e "${GRAY}   Obtén una clave reutilizable desde: https://login.tailscale.com/admin/settings/keys${RESET}"
CURRENT_AUTH=""
if [[ -f "$AUTHKEY_FILE" ]]; then
    CURRENT_AUTH=$(grep -v '^\s*#' "$AUTHKEY_FILE" | grep -v '^\s*$' | head -1 | xargs 2>/dev/null)
fi

if [[ -n "$CURRENT_AUTH" ]]; then
    echo -e "${GREEN}   ✔ Clave detectada actualmente: ${CURRENT_AUTH:0:15}...${RESET}"
    read -p "   ¿Deseas reemplazarla? (Ingresa nueva clave o presiona ENTER para mantener): " INPUT_AUTH
    AUTH_KEY="${INPUT_AUTH:-$CURRENT_AUTH}"
else
    read -p "   Pegar Auth Key (deja en blanco para configurar después): " AUTH_KEY
fi

echo ""
echo -e "${BOLD}4. URL de Inicio / Portal de Destino (Opcional)${RESET}"
echo -e "${GRAY}   (Ej: https://portal.ejemplo.com/login o deja en blanco si no aplica)${RESET}"
read -p "   URL del Portal [$CURRENT_PORTAL]: " INPUT_PORTAL
PORTAL_URL="${INPUT_PORTAL:-$CURRENT_PORTAL}"

echo ""
echo -e "${BOLD}5. Intervalo de comprobación de failover (segundos)${RESET}"
read -p "   Segundos [$CURRENT_INTERVAL]: " INPUT_INTERVAL
INTERVAL="${INPUT_INTERVAL:-$CURRENT_INTERVAL}"

# Guardar network-config.json
cat <<EOF > "$CONFIG_FILE"
{
  "network_name": "$NETWORK_NAME",
  "organization": "$ORG_NAME",
  "check_interval_seconds": $INTERVAL,
  "portal_url": "$PORTAL_URL",
  "custom_banner": true
}
EOF

# Guardar authkey.txt si se ingresó
if [[ -n "$AUTH_KEY" ]]; then
cat <<EOF > "$AUTHKEY_FILE"
# Auth Key para $NETWORK_NAME ($ORG_NAME)
$AUTH_KEY
EOF
fi

# Generar INSTRUCCIONES_CLIENTE.txt adaptado
cat <<EOF > "$GUIDE_FILE"
==============================================================================
  GUÍA FÁCIL: CÓMO CONECTARSE A LA $NETWORK_NAME
==============================================================================

¡Hola! Este programa te permite conectarte a Internet de forma segura a través 
de la red de puentes de $ORG_NAME.

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
EOF

if [[ -n "$PORTAL_URL" ]]; then
cat <<EOF >> "$GUIDE_FILE"

6. ACCEDER AL PORTAL DE INICIO:
   Una vez que la conexión sea exitosa, puedes ingresar al portal:
   👉 $PORTAL_URL
EOF
fi

cat <<EOF >> "$GUIDE_FILE"

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
EOF

echo ""
echo -e "${GREEN}==============================================================================${RESET}"
echo -e "${BOLD}${GREEN}✔ CONFIGURACIÓN GUARDADA CON ÉXITO${RESET}"
echo -e "  Red        : $NETWORK_NAME"
echo -e "  Organización: $ORG_NAME"
echo -e "  Config     : network-config.json"
echo -e "  Auth Key   : authkey.txt"
echo -e "  Guía       : INSTRUCCIONES_CLIENTE.txt"
echo -e "${GREEN}==============================================================================${RESET}"
echo ""
