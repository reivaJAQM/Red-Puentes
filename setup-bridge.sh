#!/bin/bash
# ==============================================================================
# 🌐 TAILSCALE BRIDGE SETUP  |  Configuración de Nodo Puente (Linux / macOS)
# Activación de Exit Node e IP Forwarding
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/network-config.json"
AUTHKEY_FILE="$SCRIPT_DIR/authkey.txt"

BOLD="\033[1m"
RESET="\033[0m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
GRAY="\033[0;90m"

NETWORK_NAME="Red de Puentes Tailscale"
if [[ -f "$CONFIG_FILE" ]] && command -v python3 &>/dev/null; then
    NETWORK_NAME=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('network_name', '$NETWORK_NAME'))" 2>/dev/null || echo "$NETWORK_NAME")
fi

clear
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${BOLD}${CYAN}   🌐 TAILSCALE BRIDGE SETUP  |  Configuración de Nodo Puente${RESET}"
echo -e "${CYAN}   Red: ${BOLD}${NETWORK_NAME}${RESET}"
echo -e "${GRAY}   Activación de Exit Node e IP Forwarding${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo ""

# Exigir root o sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[!] Este script requiere permisos de superusuario (root) para configurar IP forwarding.${RESET}"
    echo -e "${CYAN}[+] Reejecutando con sudo...${RESET}"
    exec sudo "$0" "$@"
fi

# --- 1. Verificar / Instalar Tailscale ---
get_tailscale_bin() {
    if command -v tailscale &>/dev/null; then
        echo "tailscale"
    elif [[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
        echo "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    elif [[ -x "/opt/homebrew/bin/tailscale" ]]; then
        echo "/opt/homebrew/bin/tailscale"
    elif [[ -x "/usr/local/bin/tailscale" ]]; then
        echo "/usr/local/bin/tailscale"
    else
        echo ""
    fi
}

TAILSCALE_BIN=$(get_tailscale_bin)
if [[ -z "$TAILSCALE_BIN" ]]; then
    echo -e "${YELLOW}[!] Tailscale no está instalado. Instalando versión oficial...${RESET}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        curl -fsSL "https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg" -o /tmp/Tailscale.pkg
        installer -pkg /tmp/Tailscale.pkg -target /
        rm -f /tmp/Tailscale.pkg
    else
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    TAILSCALE_BIN=$(get_tailscale_bin)
    if [[ -z "$TAILSCALE_BIN" ]]; then
        echo -e "${RED}[✘] Error al instalar Tailscale.${RESET}"
        exit 1
    fi
fi
echo -e "${GREEN}[✔] Tailscale verificado en: ${TAILSCALE_BIN}${RESET}"

# --- 2. Habilitar IP Forwarding en el Sistema Operativo ---
echo -e "${GRAY}[+] Configurando IP Forwarding no kernel...${RESET}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    sysctl -w net.inet.ip.forwarding=1 &>/dev/null
    sysctl -w net.inet6.ip6.forwarding=1 &>/dev/null
else
    sysctl -w net.ipv4.ip_forward=1 &>/dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 &>/dev/null
    # Persistir en sysctl.conf si aplica
    if [[ -f /etc/sysctl.conf ]]; then
        grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
fi
echo -e "${GREEN}[✔] IP Forwarding habilitado correctamente.${RESET}"

# --- 3. Leer o solicitar Auth Key ---
AUTH_KEY=""
if [[ -f "$AUTHKEY_FILE" ]]; then
    AUTH_KEY=$(grep -v '^\s*#' "$AUTHKEY_FILE" | grep -v '^\s*$' | head -1 | xargs 2>/dev/null)
fi

if [[ -z "$AUTH_KEY" ]]; then
    echo ""
    echo -e "${YELLOW}[!] No se encontró ninguna Auth Key en authkey.txt.${RESET}"
    echo -e "${GRAY}    Para conectar este puente automáticamente a tu red, necesitas una Auth Key de Tailscale.${RESET}"
    echo -e "${GRAY}    Genera una clave en: https://login.tailscale.com/admin/settings/keys${RESET}"
    read -p "Ingresa tu Auth Key: " AUTH_KEY
fi

if [[ -n "$AUTH_KEY" ]]; then
    echo -e "${YELLOW}[+] Autenticando nodo puente con la Auth Key...${RESET}"
    "$TAILSCALE_BIN" up --authkey="$AUTH_KEY" --accept-routes --advertise-exit-node --unattended --reset --force-reauth
fi

status_json=$("$TAILSCALE_BIN" status --json 2>/dev/null)
if ! echo "$status_json" | grep -q '"BackendState": *"Running"'; then
    echo -e "${RED}[✘] Error de autenticación. Verifica tu Auth Key o tu consola de Tailscale.${RESET}"
    exit 2
fi
echo -e "${GREEN}[✔] Sesión autenticada en el Tailnet.${RESET}"

# --- 4. Asegurar flags exit-node ---
"$TAILSCALE_BIN" set --advertise-exit-node --unattended

BRIDGE_IP=$("$TAILSCALE_BIN" ip -4 2>/dev/null || echo "Desconocida")
HOSTNAME_NAME=$(hostname)

echo ""
echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│${RESET} ${GREEN}${BOLD}✔ PUENTE CONFIGURADO CON ÉXITO${RESET}                                           ${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET}   Red         : ${NETWORK_NAME}                                          ${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET}   Nodo        : ${HOSTNAME_NAME}                                          ${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET}   IP Tailscale: ${BRIDGE_IP}                                            ${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET}   Estado      : Operando como Exit Node (Silencioso / Unattended)         ${CYAN}│${RESET}"
echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────┘${RESET}"
echo ""
echo -e "${GRAY}Recuerda aprobar este nodo como Exit Node en el panel web si tu tailnet lo requiere:${RESET}"
echo -e "${CYAN}👉 https://login.tailscale.com/admin/machines${RESET}"
echo ""
