#!/bin/bash
# ==============================================================================
# 🌐 TAILSCALE BRIDGE CLIENT (macOS / Linux)
# Enrutamiento Inteligente con Failover Automático
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/network-config.json"
BRIDGES_FILE="$SCRIPT_DIR/bridges.txt"
AUTHKEY_FILE="$SCRIPT_DIR/authkey.txt"

# Colores ANSI
BOLD="\033[1m"
RESET="\033[0m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
MAGENTA="\033[1;35m"
GRAY="\033[0;90m"
WHITE_BG="\033[47;30m"
GREEN_BG="\033[42;30m"

# Leer configuración dinámica
NETWORK_NAME="Red de Puentes Tailscale"
CHECK_INTERVAL=30
PORTAL_URL=""

if [[ -f "$CONFIG_FILE" ]] && command -v python3 &>/dev/null; then
    NETWORK_NAME=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('network_name', '$NETWORK_NAME'))" 2>/dev/null || echo "$NETWORK_NAME")
    CHECK_INTERVAL=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('check_interval_seconds', 30))" 2>/dev/null || echo "30")
    PORTAL_URL=$(python3 -c "import json; data=json.load(open('$CONFIG_FILE')); print(data.get('portal_url', ''))" 2>/dev/null || echo "")
fi

# Título y Encabezado
print_banner() {
    clear
    echo -e "${CYAN}==============================================================================${RESET}"
    echo -e "${BOLD}${CYAN}   🌐 TAILSCALE BRIDGE CLIENT  |  ${NETWORK_NAME}${RESET}"
    echo -e "${GRAY}   Enrutamiento Inteligente con Failover Automático y Alta Disponibilidad${RESET}"
    echo -e "${CYAN}==============================================================================${RESET}"
    echo ""
}

print_banner

# --- Función para obtener el ejecutable de Tailscale ---
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

# --- Instalar / Detectar Tailscale ---
echo -e "${GRAY}[1/3] Verificando servicio de Tailscale...${RESET}"
TAILSCALE_BIN=$(get_tailscale_bin)

if [[ -z "$TAILSCALE_BIN" ]]; then
    echo -e "${YELLOW}[!] Tailscale no está instalado. Iniciando descarga e instalación...${RESET}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        installed=0

        BREW_BIN=""
        if command -v brew &>/dev/null; then
            BREW_BIN="brew"
        elif [[ -x "/opt/homebrew/bin/brew" ]]; then
            BREW_BIN="/opt/homebrew/bin/brew"
        elif [[ -x "/usr/local/bin/brew" ]]; then
            BREW_BIN="/usr/local/bin/brew"
        fi

        if [[ -n "$BREW_BIN" ]]; then
            echo -e "${CYAN}[+] Instalando Tailscale con Homebrew...${RESET}"
            if [[ -n "$SUDO_USER" ]]; then
                sudo -u "$SUDO_USER" "$BREW_BIN" install --cask tailscale && installed=1
            else
                "$BREW_BIN" install --cask tailscale && installed=1
            fi
        fi

        if [[ $installed -eq 0 ]]; then
            echo -e "${CYAN}[+] Descargando paquete oficial (.pkg) de Tailscale para macOS...${RESET}"
            curl -fsSL "https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg" -o /tmp/Tailscale.pkg
            echo -e "${CYAN}[+] Instalando paquete en el sistema...${RESET}"
            sudo installer -pkg /tmp/Tailscale.pkg -target / 2>/dev/null || installer -pkg /tmp/Tailscale.pkg -target /
            rm -f /tmp/Tailscale.pkg
        fi

        if [[ -d "/Applications/Tailscale.app" ]]; then
            if [[ -n "$SUDO_USER" ]]; then
                sudo -u "$SUDO_USER" open -a Tailscale 2>/dev/null || true
            else
                open -a Tailscale 2>/dev/null || true
            fi
            sleep 3
        fi
    else
        echo -e "${CYAN}[+] Instalando Tailscale para Linux...${RESET}"
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    TAILSCALE_BIN=$(get_tailscale_bin)
    if [[ -z "$TAILSCALE_BIN" ]]; then
        echo -e "${RED}[✘] No se pudo encontrar el ejecutable de Tailscale tras la instalación.${RESET}"
        exit 1
    fi
    echo -e "${GREEN}[✔] Tailscale instalado correctamente en: ${TAILSCALE_BIN}${RESET}"
else
    echo -e "${GREEN}[✔] Tailscale detectado en: ${TAILSCALE_BIN}${RESET}"
fi

# --- Función para ejecutar comandos de Tailscale con el usuario adecuado ---
run_tailscale() {
    if [[ -n "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" "$TAILSCALE_BIN" "$@" 2>/dev/null
    else
        "$TAILSCALE_BIN" "$@" 2>/dev/null
    fi
}

# --- Autenticar / Reautenticar automáticamente ---
echo -e "${GRAY}[2/3] Verificando sesión y alcanzabilidad de la red...${RESET}"

need_login=0
if ! run_tailscale status --json | grep -q '"BackendState": *"Running"'; then
    need_login=1
else
    if ! run_tailscale status --json | grep -q '"ExitNodeOption": *true'; then
        bridges_reachable=0
        if [[ -f "$BRIDGES_FILE" ]]; then
            while IFS= read -r b; do
                if [[ -n "$b" ]] && ping -c 1 -W 2 "$b" &>/dev/null; then
                    bridges_reachable=1
                    break
                fi
            done < <(grep -v '^\s*#' "$BRIDGES_FILE" | grep -v '^\s*$' | tr -d ' ')
        fi
        if [[ $bridges_reachable -eq 0 ]]; then
            echo -e "${YELLOW}[!] Sesión activa en Tailscale pero no se detectan los puentes de la red.${RESET}"
            need_login=1
        fi
    fi
fi

if [[ $need_login -eq 1 ]]; then
    authKey=""
    if [[ -f "$AUTHKEY_FILE" ]]; then
        authKey=$(grep -v '^\s*#' "$AUTHKEY_FILE" | grep -v '^\s*$' | head -1 | xargs 2>/dev/null)
    fi

    if [[ -z "$authKey" ]]; then
        echo ""
        echo -e "${YELLOW}[!] No se encontró ninguna Auth Key en authkey.txt.${RESET}"
        echo -e "${GRAY}    Genera una Auth Key en: https://login.tailscale.com/admin/settings/keys${RESET}"
        read -p "Ingresa tu Auth Key: " authKey
    fi

    if [[ -n "$authKey" ]]; then
        echo -e "${YELLOW}[+] Conectando a la red con Auth Key (--reset --force-reauth)...${RESET}"
        run_tailscale up --authkey "$authKey" --reset --force-reauth
        sleep 2
        if ! run_tailscale status --json | grep -q '"BackendState": *"Running"'; then
            echo -e "${YELLOW}[!] Reintentando autenticación tras reiniciar estado local...${RESET}"
            run_tailscale logout 2>/dev/null
            sleep 1
            run_tailscale up --authkey "$authKey" --reset --force-reauth
            sleep 2
        fi
    fi
    if ! run_tailscale status --json | grep -q '"BackendState": *"Running"'; then
        echo -e "${RED}[✘] Error: No se pudo autenticar en Tailscale.${RESET}"
        echo -e "${GRAY}    Verifica la Auth Key en authkey.txt${RESET}"
        exit 1
    fi
fi
echo -e "${GREEN}[✔] Sesión activa y conectada en la red.${RESET}"

# --- Autodetectar puentes (Exit Nodes) en la red ---
echo -e "${GRAY}[3/3] Autodetectando puentes disponibles en la red...${RESET}"
detected_bridges=()

if command -v python3 &>/dev/null; then
    json_status=$(run_tailscale status --json)
    if [[ -n "$json_status" ]]; then
        while IFS= read -r host; do
            [[ -n "$host" ]] && detected_bridges+=("$host")
        done < <(echo "$json_status" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    peers = data.get('Peer', {})
    for k, v in peers.items():
        if v.get('ExitNodeOption'):
            print(v.get('HostName'))
except Exception:
    pass
" 2>/dev/null)
    fi
fi

if [[ ${#detected_bridges[@]} -gt 0 ]]; then
    printf "%s\n" "${detected_bridges[@]}" > "$BRIDGES_FILE"
    echo -e "${GREEN}[✔] Puentes autodetectados en vivo y guardados en bridges.txt (${#detected_bridges[@]}): ${detected_bridges[*]}${RESET}"
fi

bridges=()
if [[ -f "$BRIDGES_FILE" ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && bridges+=("$line")
    done < <(grep -v '^\s*#' "$BRIDGES_FILE" | grep -v '^\s*$' | tr -d ' ')
fi

if [[ ${#bridges[@]} -eq 0 ]]; then
    echo -e "${RED}[✘] No se encontraron puentes activos en la red ni en bridges.txt.${RESET}"
    echo -e "${GRAY}    Asegúrate de iniciar al menos un nodo puente (setup-bridge).${RESET}"
    exit 1
fi
echo -e "${GREEN}[✔] Puentes activos configurados: ${bridges[*]}${RESET}"
echo ""

# --- Trap de desconexión automática al cerrar terminal o interrumpir (Ctrl+C) ---
cleanup() {
    trap - INT TERM EXIT
    echo ""
    echo -e "${YELLOW}==============================================================================${RESET}"
    echo -e "${YELLOW}[+] Desconectando del puente de salida...${RESET}"
    run_tailscale set --exit-node=""
    echo -e "${GREEN}[✔] Desconectado con éxito. Tu tráfico ha vuelto a tu red habitual.${RESET}"
    echo -e "${YELLOW}==============================================================================${RESET}"
    exit 0
}

trap cleanup INT TERM EXIT

echo -e "${GREEN_BG}${BOLD}  STATUS: CONEXIÓN ACTIVA  ${RESET}  ${GRAY}Monitoreo de failover en ejecución (cada ${CHECK_INTERVAL}s)${RESET}"
echo -e "${MAGENTA} Presiona [ Q ] o [ Ctrl+C ] en esta ventana para desconectarte y salir.${RESET}"
echo -e "${GRAY}------------------------------------------------------------------------------${RESET}"

# --- Loop de failover ---
current_node=""
first_connect=1
while true; do
    alive_node=""
    timestamp=$(date +"%H:%M:%S")

    for b in "${bridges[@]}"; do
        echo -e "${GRAY}[${timestamp}]  Probando disponibilidad de puente: ${CYAN}${b}${RESET}"
        if ping -c 1 -W 2 "$b" &>/dev/null; then
            alive_node="$b"
            echo -e "${GREEN}[${timestamp}] ✔ Puente respondiendo: ${b}${RESET}"
            break
        else
            echo -e "${YELLOW}[${timestamp}] ✖ Puente sin respuesta: ${b}${RESET}"
        fi
    done

    if [[ -z "$alive_node" ]]; then
        echo -e "${RED}[!]   Ningún puente disponible en este momento. Reintentando...${RESET}"
    elif [[ "$alive_node" != "$current_node" ]]; then
        echo -e "${GREEN}[+]  Estableciendo salida de red a través de: ${BOLD}${CYAN}${alive_node}${RESET}"
        if run_tailscale set --exit-node="$alive_node"; then
            current_node="$alive_node"
            echo ""
            echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────────┐${RESET}"
            echo -e "${CYAN}│${RESET} ${GREEN}${BOLD}✔ CONECTADO EXITOSAMENTE AL PUENTE${RESET}                                 ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET}  Node Activo : ${BOLD}${WHITE_BG} ${alive_node} ${RESET}                                  ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET}  Estado      : Enrutando todo el tráfico de forma segura                ${CYAN}│${RESET}"
            echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────┘${RESET}"
            echo ""
            
            if [[ $first_connect -eq 1 ]] && [[ -n "$PORTAL_URL" ]]; then
                first_connect=0
                echo -e "${CYAN}[🌐] Abriendo portal de la red: ${PORTAL_URL}${RESET}"
                open "$PORTAL_URL" 2>/dev/null || xdg-open "$PORTAL_URL" 2>/dev/null || true
            fi
        else
            echo -e "${RED}[✘] Error al conectar con el puente ${alive_node}.${RESET}"
        fi
    fi

    # Esperar el intervalo escuchando la tecla 'Q' o 'q' por segundo
    for ((i=0; i<CHECK_INTERVAL; i++)); do
        read -t 1 -n 1 -r key 2>/dev/null
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            cleanup
        fi
    done
done
