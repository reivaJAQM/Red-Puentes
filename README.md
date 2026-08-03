# Tailscale Bridge Network Kit (Universal & Portátil)

Sistema autónomo, portátil y universal para crear y administrar tu propia **Red de Puentes (Exit Nodes) con Tailscale** con conmutación por error (failover) en tiempo real, autodetección de nodos y portabilidad total.

Diseñado para que **cualquier persona, empresa u organización** pueda desplegar una infraestructura de red segura y distribuida en cuestión de minutos.

---

## Inicio Rápido en 3 Pasos

### 1. Configurar tu Red (Asistente en 1 minuto)

Ejecuta el asistente interactivo para definir el nombre de tu red, tu Auth Key de Tailscale y portal opcional:

* **Windows**: Doble clic en `configure.bat`
* **Mac / Linux**: Abre una terminal y ejecuta `./configure.sh`

> **Nota**: Puedes obtener una *Auth Key reutilizable* de Tailscale desde [Tailscale Admin Keys](https://login.tailscale.com/admin/settings/keys).

---

### 2. Desplegar los Nodos Puente (Exit Nodes)

Lleva el script de puente a la(s) computadora(s) que actuarán como servidores o puentes de salida a Internet:

* **Windows**: Ejecuta `setup-bridge.bat` (Doble clic, auto-eleva permisos de administrador).
* **Linux / Mac**: Ejecuta `sudo ./setup-bridge.sh`.

**Lo que realiza el script puente**:
* Instala Tailscale automáticamente si no está instalado.
* Se autentica silenciosamente en la red con la *Auth Key* configurada.
* Activa **Exit Node** e **IP Forwarding** en el sistema operativo.
* Desactiva la suspensión del sistema (`powercfg` / `sysctl`) para mantener el puente siempre activo.
* **Cero rastro**: No deja archivos residuales innecesarios.

> *Recuerda aprobar los nodos como exit node en el panel web si tu tailnet lo requiere: [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines).*

---

### 3. Conectar a los Usuarios Clientes

Entrega la carpeta o los ejecutables portátiles a tus usuarios finales:

* **Clientes Windows**: Ejecutar `setup-client.bat`
* **Clientes Mac**: Ejecutar `setup-client.command` (desde el Finder o Terminal)

**Lo que realiza el script cliente**:
1. Instala e inicia Tailscale en segundo plano si no se detecta en el equipo.
2. Conecta automáticamente a la red configurada.
3. **Autodetección en vivo**: Descubre todos los puentes activos en la red y los guarda en `bridges.txt`.
4. Conecta al primer puente disponible y enruta el tráfico de forma segura.
5. **Monitoreo & Failover**: Si un puente se desconecta o apaga, conmuta al instante al siguiente puente disponible sin interrumpir al usuario.
6. **Desconexión en 1 clic**: El usuario presiona **`Q`**, **`Ctrl+C`** o cierra la ventana para desconectarse inmediatamente y restaurar su conexión local.

---

## Estructura del Proyecto

```text
Tailscale-Bridge-Kit/
├── configure.bat           <- Asistente de configuración rápida (Windows)
├── configure.sh            <- Asistente de configuración rápida (Mac/Linux)
├── network-config.json     <- Archivo de configuración centralizado (Nombre, portal, tiempos)
├── authkey.txt             <- Clave de autenticación reutilizable de Tailscale
├── bridges.txt             <- Lista de puentes activos (autodetectada en vivo)
├── setup-bridge.bat        <- Instalador de NODO PUENTE (Windows)
├── setup-bridge.sh         <- Instalador de NODO PUENTE (Linux / Mac)
├── setup-client.bat        <- CLIENTE portátil con failover (Windows)
├── setup-client.command    <- CLIENTE portátil con failover (Mac)
├── INSTRUCCIONES_CLIENTE.txt <- Guía fácil no técnica generada para usuarios finales
└── README.md               <- Documentación técnica universal
```

---

## Archivo de Configuración (`network-config.json`)

Puedes editar manualmente `network-config.json` o utilizar el asistente `configure.bat` / `configure.sh`:

```json
{
  "network_name": "Red de Puentes MiEmpresa",
  "organization": "Mi Organización",
  "check_interval_seconds": 30,
  "portal_url": "https://mi-portal.com",
  "custom_banner": true
}
```

* `network_name`: El nombre que verán los usuarios en las pantallas de conexión.
* `check_interval_seconds`: Frecuencia (en segundos) de verificación de salud del puente activo.
* `portal_url`: URL opcional que se abrirá automáticamente en el navegador al conectarse con éxito.

---

## Verificación de Conexión

Desde cualquier cliente conectado, puedes verificar tu IP pública navegando a [https://ipinfo.io](https://ipinfo.io) o [https://ifconfig.me](https://ifconfig.me) — debe mostrar la ubicación e IP pública del nodo puente activo.

---

## Seguridad y Privacidad

* **Cifrado End-to-End**: Todo el tráfico entre clientes y puentes se cifra utilizando el protocolo seguro WireGuard® de Tailscale.
* **Control total**: El administrador de la Tailnet controla qué nodos pueden actuar como puentes y qué usuarios pueden acceder.
* **Cero Residuo**: Desconectarse remueve la configuración de salida y devuelve al usuario a su interfaz de red original.
