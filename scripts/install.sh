#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#   COCO - Attack & Defense Platform
#   Installer v0.1.0
#   Target: Debian 13 (Trixie)
# ============================================================

COCO_VERSION="0.1.0"
COCO_DIR="/opt/coco"
LOG_FILE="/var/log/coco-install.log"
REQUIRED_RAM_GB=16
REQUIRED_DISK_GB=50

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }
info()    { echo -e "${CYAN}  [*]${RESET} $*"; log "INFO: $*"; }
success() { echo -e "${GREEN}  [+]${RESET} $*"; log "OK:   $*"; }
warn()    { echo -e "${YELLOW}  [!]${RESET} $*"; log "WARN: $*"; }
error()   { echo -e "${RED}  [-] ERROR: $*${RESET}"; log "ERR:  $*"; exit 1; }

print_logo() {
    clear
    echo -e "${CYAN}"
    cat << 'LOGO'
  ██████╗  ██████╗  ██████╗  ██████╗
 ██╔════╝ ██╔═══██╗██╔════╝ ██╔═══██╗
 ██║      ██║   ██║██║      ██║   ██║
 ██║      ██║   ██║██║      ██║   ██║
 ╚██████╗ ╚██████╔╝╚██████╗ ╚██████╔╝
  ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝
         Attack & Defense Platform
LOGO
    echo -e "${RESET}"
    echo -e "  ${BOLD}Version${RESET}  ${COCO_VERSION}"
    echo -e "  ${BOLD}Target${RESET}   Debian 13 (Trixie)"
    echo -e "  ${BOLD}Log${RESET}      ${LOG_FILE}"
    echo -e "  ${CYAN}────────────────────────────────────────────${RESET}"
    echo ""
}

check_root() {
    [[ $EUID -eq 0 ]] || error "This installer must be run as root.  Try: sudo bash install.sh"
}

check_os() {
    info "Checking operating system..."
    [[ -f /etc/debian_version ]] || error "Requires Debian Linux. Detected: $(uname -s)"
    success "Debian $(cat /etc/debian_version)"
}

check_resources() {
    info "Checking system resources..."

    local ram_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    if [[ $ram_gb -lt $REQUIRED_RAM_GB ]]; then
        warn "RAM: ${ram_gb} GB detected — recommended minimum is ${REQUIRED_RAM_GB} GB"
    else
        success "RAM: ${ram_gb} GB"
    fi

    local disk_gb
    disk_gb=$(df / --output=avail -BG | tail -1 | tr -d 'G ')
    if [[ $disk_gb -lt $REQUIRED_DISK_GB ]]; then
        error "Not enough disk space: ${disk_gb} GB free, ${REQUIRED_DISK_GB} GB required"
    else
        success "Disk: ${disk_gb} GB available"
    fi

    if grep -qE 'vmx|svm' /proc/cpuinfo; then
        success "Nested virtualization: CPU flags present (vmx/svm)"
    else
        warn "No vmx/svm CPU flags detected"
        warn "Make sure Proxmox CPU type is set to 'host' for this VM"
    fi
}

prompt_config() {
    echo ""
    echo -e "  ${BOLD}Configuration${RESET}"
    echo -e "  ${CYAN}────────────────────────────────────────────${RESET}"

    read -rp "  COCO VM IP address   [192.168.118.133]: " COCO_IP
    COCO_IP=${COCO_IP:-192.168.118.133}

    read -rp "  COCO Web-GUI port    [8080]: " COCO_PORT
    COCO_PORT=${COCO_PORT:-8080}

    read -rp "  Proxmox host IP      [192.168.118.1]: " PROXMOX_HOST
    PROXMOX_HOST=${PROXMOX_HOST:-192.168.118.1}

    read -rp "  Proxmox API user     [root@pam]: " PROXMOX_USER
    PROXMOX_USER=${PROXMOX_USER:-root@pam}

    read -rsp "  Proxmox password: " PROXMOX_PASSWORD
    echo ""

    SECRET_KEY=$(openssl rand -hex 32)

    echo ""
    echo -e "  ${BOLD}Summary${RESET}"
    echo -e "  ${CYAN}────────────────────────────────────────────${RESET}"
    echo -e "  COCO Web-GUI  :  ${CYAN}http://${COCO_IP}:${COCO_PORT}${RESET}"
    echo -e "  Guacamole     :  ${CYAN}http://${COCO_IP}:8443${RESET}"
    echo -e "  Proxmox Host  :  ${PROXMOX_HOST}"
    echo -e "  Install dir   :  ${COCO_DIR}"
    echo ""
    read -rp "  Proceed with installation? [y/N]: " confirm
    [[ "${confirm,,}" == "y" ]] || error "Installation cancelled."
}

install_dependencies() {
    info "Updating package index..."
    apt-get update -qq >> "$LOG_FILE" 2>&1

    info "Installing system packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget git vim \
        apt-transport-https ca-certificates gnupg lsb-release \
        python3 python3-pip python3-venv \
        qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
        bridge-utils vlan unzip jq openssl \
        >> "$LOG_FILE" 2>&1
    success "System packages installed"

    info "Installing Docker..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
        systemctl enable --now docker >> "$LOG_FILE" 2>&1
    fi
    success "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

    info "Installing Ansible..."
    pip3 install --quiet ansible >> "$LOG_FILE" 2>&1
    success "Ansible $(ansible --version | head -1 | awk '{print $2}')"

    info "Installing Packer..."
    if ! command -v packer &>/dev/null; then
        local PACKER_VER="1.11.0"
        wget -q "https://releases.hashicorp.com/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip" \
            -O /tmp/packer.zip >> "$LOG_FILE" 2>&1
        unzip -q /tmp/packer.zip -d /usr/local/bin/
        rm /tmp/packer.zip
        chmod +x /usr/local/bin/packer
    fi
    success "Packer $(packer --version)"
}

setup_network() {
    info "Configuring game bridge (br-game)..."

    cat > /etc/network/interfaces.d/coco-bridge.cfg << NETCFG
auto br-game
iface br-game inet static
    address 10.10.0.1
    netmask 255.255.0.0
    bridge_ports none
    bridge_stp off
    bridge_fd 0
NETCFG

    ip link add br-game type bridge 2>/dev/null || true
    ip addr add 10.10.0.1/16 dev br-game 2>/dev/null || true
    ip link set br-game up

    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-coco.conf
    sysctl -p /etc/sysctl.d/99-coco.conf >> "$LOG_FILE" 2>&1

    success "Bridge br-game ready (10.10.0.0/16)"
}

setup_coco_dir() {
    info "Creating COCO directory at ${COCO_DIR}..."
    mkdir -p "${COCO_DIR}"

    info "Writing environment config..."
    cat > "${COCO_DIR}/.env" << ENVEOF
SECRET_KEY=${SECRET_KEY}
PROXMOX_HOST=${PROXMOX_HOST}
PROXMOX_USER=${PROXMOX_USER}
PROXMOX_PASSWORD=${PROXMOX_PASSWORD}
PROXMOX_NODE=pve
COCO_IP=${COCO_IP}
COCO_PORT=${COCO_PORT}
GAME_BRIDGE=br-game
GAME_NETWORK=10.10.0.0/16
AD_VLAN=10
WEBAPP_VLAN=20
DB_VLAN=30
ENVEOF
    chmod 600 "${COCO_DIR}/.env"
    success "Config written to ${COCO_DIR}/.env (permissions: 600)"
}

print_done() {
    echo ""
    echo -e "${GREEN}"
    cat << 'DONE'
  ────────────────────────────────────────────
   Installation complete.
  ────────────────────────────────────────────
DONE
    echo -e "${RESET}"
    echo -e "  Web-GUI    :  ${CYAN}http://${COCO_IP}:${COCO_PORT}${RESET}"
    echo -e "  Guacamole  :  ${CYAN}http://${COCO_IP}:8443${RESET}"
    echo -e "  Config     :  ${COCO_DIR}/.env"
    echo -e "  Logs       :  ${LOG_FILE}"
    echo ""
    echo -e "  ${YELLOW}Next step:${RESET}"
    echo -e "  cd ${COCO_DIR} && docker compose up -d"
    echo ""
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    print_logo
    check_root
    check_os
    check_resources
    prompt_config
    install_dependencies
    setup_network
    setup_coco_dir
    print_done
}

main "$@"
