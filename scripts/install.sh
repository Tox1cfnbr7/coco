#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#   COCO - Attack & Defense Platform
#   Installer v0.2.0
#   Target: Debian 13 (Trixie)
#   Installs: Proxmox VE 9, KVM/libvirt, Docker,
#             Ansible, Packer, COCO Stack
# ============================================================

COCO_VERSION="0.2.0"
COCO_DIR="/opt/coco"
LOG_FILE="/var/log/coco-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Logging ────────────────────────────────────────────────
log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }
info()    { echo -e "${CYAN}  [*]${RESET} $*"; log "INFO: $*"; }
success() { echo -e "${GREEN}  [+]${RESET} $*"; log "OK:   $*"; }
warn()    { echo -e "${YELLOW}  [!]${RESET} $*"; log "WARN: $*"; }
error()   { echo -e "${RED}  [-] $*${RESET}"; log "ERR:  $*"; exit 1; }
step()    { echo ""; echo -e "  ${BOLD}${CYAN}>> $*${RESET}"; echo ""; }
divider() { echo -e "  ${DIM}────────────────────────────────────────────────${RESET}"; }

# ── Logo ───────────────────────────────────────────────────
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
    echo -e "  ${BOLD}Version${RESET}  ${COCO_VERSION}  |  ${BOLD}Target${RESET}  Debian 13  |  ${BOLD}Log${RESET}  ${LOG_FILE}"
    divider
    echo ""
}

# ── Preflight ──────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || error "Run as root: sudo bash install.sh"
}

check_os() {
    step "System check"
    [[ -f /etc/debian_version ]] || error "Requires Debian 13. Detected: $(uname -s)"
    local ver
    ver=$(cat /etc/debian_version)
    success "OS: Debian ${ver}"

    local ram_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    [[ $ram_gb -lt 8 ]] && warn "RAM: ${ram_gb} GB — recommended 16+ GB" || success "RAM: ${ram_gb} GB"

    local disk_gb
    disk_gb=$(df / --output=avail -BG | tail -1 | tr -d 'G ')
    [[ $disk_gb -lt 50 ]] && error "Disk: only ${disk_gb} GB free — need 50+ GB" || success "Disk: ${disk_gb} GB free"

    if grep -qE 'vmx|svm' /proc/cpuinfo; then
        success "CPU: Nested virtualization flags present (vmx/svm)"
    else
        warn "CPU: No vmx/svm flags — make sure Proxmox CPU type is set to 'host'"
    fi
}

# ── Interactive Config ─────────────────────────────────────
collect_config() {
    step "Configuration"
    echo -e "  ${DIM}Press Enter to accept the default value shown in brackets.${RESET}"
    echo ""

    # Network
    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')

    read -rp "  $(echo -e "${BOLD}COCO VM IP address${RESET}") [${detected_ip}]: " COCO_IP
    COCO_IP=${COCO_IP:-$detected_ip}

    read -rp "  $(echo -e "${BOLD}COCO Web-GUI port${RESET}") [8080]: " COCO_PORT
    COCO_PORT=${COCO_PORT:-8080}

    # Proxmox
    echo ""
    echo -e "  ${DIM}Proxmox VE will be installed on this machine.${RESET}"
    echo -e "  ${DIM}The hostname will become the Proxmox node name.${RESET}"
    echo ""

    local detected_hostname
    detected_hostname=$(hostname)

    read -rp "  $(echo -e "${BOLD}Proxmox hostname${RESET}") [${detected_hostname}]: " PVE_HOSTNAME
    PVE_HOSTNAME=${PVE_HOSTNAME:-$detected_hostname}

    read -rsp "  $(echo -e "${BOLD}Proxmox root password${RESET}"): " PVE_ROOT_PASSWORD
    echo ""
    read -rsp "  $(echo -e "${BOLD}Confirm password${RESET}"): " PVE_ROOT_PASSWORD_CONFIRM
    echo ""

    [[ "$PVE_ROOT_PASSWORD" == "$PVE_ROOT_PASSWORD_CONFIRM" ]] || error "Passwords do not match."
    [[ ${#PVE_ROOT_PASSWORD} -ge 8 ]] || error "Password must be at least 8 characters."

    # Generate secret
    SECRET_KEY=$(openssl rand -hex 32)

    # Summary
    echo ""
    step "Summary"
    divider
    echo -e "  COCO Web-GUI     :  ${CYAN}http://${COCO_IP}:${COCO_PORT}${RESET}"
    echo -e "  Guacamole        :  ${CYAN}http://${COCO_IP}:8443${RESET}"
    echo -e "  Proxmox hostname :  ${PVE_HOSTNAME}"
    echo -e "  Proxmox GUI      :  ${CYAN}https://${COCO_IP}:8006${RESET}"
    echo -e "  Install dir      :  ${COCO_DIR}"
    divider
    echo ""
    read -rp "  Proceed with installation? [y/N]: " confirm
    [[ "${confirm,,}" == "y" ]] || error "Installation cancelled."
}

# ── Proxmox VE 9 ───────────────────────────────────────────
install_proxmox() {
    step "Installing Proxmox VE 9 on Debian 13 (Trixie)"

    info "Setting hostname to ${PVE_HOSTNAME}..."
    hostnamectl set-hostname "${PVE_HOSTNAME}"
    cat > /etc/hosts << HOSTSEOF
127.0.0.1       localhost
${COCO_IP}      ${PVE_HOSTNAME}.local ${PVE_HOSTNAME}

::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
HOSTSEOF
    success "Hostname set — $(hostname --ip-address)"

    info "Cleaning existing apt sources..."
    rm -f /etc/apt/sources.list.d/pve-install-repo.list
    rm -f /etc/apt/sources.list.d/pve-install-repo.sources
    rm -f /etc/apt/sources.list.d/pve-enterprise.list
    rm -f /etc/apt/sources.list.d/ceph.list
    rm -f /etc/apt/trusted.gpg.d/proxmox-*.gpg
    success "Old sources cleaned"

    info "Adding Proxmox VE repository (Trixie)..."
    cat > /etc/apt/sources.list.d/pve-install-repo.sources << REPOEOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
REPOEOF
    success "Repository configured"

    info "Downloading Proxmox GPG key (Trixie)..."
    wget --no-check-certificate -q \
        https://download.proxmox.com/debian/proxmox-release-trixie.gpg \
        -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
    success "GPG key installed"

    info "Removing enterprise repository if present..."
    rm -f /etc/apt/sources.list.d/pve-enterprise.list
    rm -f /etc/apt/sources.list.d/ceph.list
    find /etc/apt/sources.list.d/ -name "*.sources" \
        -exec grep -l "enterprise.proxmox.com" {} \; | xargs rm -f 2>/dev/null || true
    success "Enterprise repository removed"

    info "Updating package index and upgrading base system..."
    apt-get update -qq >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq >> "$LOG_FILE" 2>&1
    success "Base system up to date"

    info "Installing Proxmox VE kernel (reboot required after)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-default-kernel \
        >> "$LOG_FILE" 2>&1
    success "Proxmox kernel installed"

    info "Installing Proxmox VE packages (this takes a few minutes)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        proxmox-ve postfix open-iscsi chrony \
        >> "$LOG_FILE" 2>&1
    success "Proxmox VE installed"

    info "Setting root password..."
    echo "root:${PVE_ROOT_PASSWORD}" | chpasswd
    success "Root password set"

    info "Removing Debian default kernel..."
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        linux-image-amd64 'linux-image-6.12*' >> "$LOG_FILE" 2>&1 || true
    update-grub >> "$LOG_FILE" 2>&1
    success "Debian kernel removed — Proxmox kernel active"

    info "Removing os-prober (can cause issues with VM disks in GRUB)..."
    apt-get remove -y os-prober >> "$LOG_FILE" 2>&1 || true
    success "os-prober removed"
}

# ── Post-Proxmox config ────────────────────────────────────
configure_system() {
    step "Configuring system"

    info "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-coco.conf
    sysctl -p /etc/sysctl.d/99-coco.conf >> "$LOG_FILE" 2>&1
    success "IP forwarding enabled"

    info "Installing base tools..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget git vim unzip jq openssl \
        >> "$LOG_FILE" 2>&1
    success "Base tools installed"
}

# ── Docker ─────────────────────────────────────────────────
install_docker() {
    step "Installing Docker"

    if command -v docker &>/dev/null; then
        success "Docker already installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        return
    fi

    info "Downloading and running Docker install script..."
    curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
    systemctl enable --now docker >> "$LOG_FILE" 2>&1
    success "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
}

# ── Ansible ────────────────────────────────────────────────
install_ansible() {
    step "Installing Ansible"

    if command -v ansible &>/dev/null; then
        success "Ansible already installed"
        return
    fi

    apt-get install -y -qq python3 python3-pip python3-venv >> "$LOG_FILE" 2>&1
    pip3 install --quiet ansible >> "$LOG_FILE" 2>&1
    success "Ansible $(ansible --version | head -1 | awk '{print $2}')"
}

# ── Packer ─────────────────────────────────────────────────
install_packer() {
    step "Installing Packer"

    if command -v packer &>/dev/null; then
        success "Packer already installed"
        return
    fi

    local PACKER_VER="1.11.0"
    info "Downloading Packer ${PACKER_VER}..."
    wget -q "https://releases.hashicorp.com/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip" \
        -O /tmp/packer.zip
    unzip -q /tmp/packer.zip -d /usr/local/bin/
    rm /tmp/packer.zip
    chmod +x /usr/local/bin/packer
    success "Packer $(packer --version)"
}

# ── COCO Stack ─────────────────────────────────────────────
setup_coco() {
    step "Setting up COCO"

    info "Creating directory structure..."
    mkdir -p "${COCO_DIR}"/{docker,ansible,packer,configs}

    info "Writing environment config..."
    cat > "${COCO_DIR}/.env" << ENVEOF
# COCO Environment — generated by install.sh
# $(date)

SECRET_KEY=${SECRET_KEY}

COCO_IP=${COCO_IP}
COCO_PORT=${COCO_PORT}

PVE_HOSTNAME=${PVE_HOSTNAME}
PVE_NODE=${PVE_HOSTNAME}

# Game network is configured via COCO Web-GUI, not here.
ENVEOF
    chmod 600 "${COCO_DIR}/.env"
    success "Config written to ${COCO_DIR}/.env"

    info "Cloning COCO repository..."
    if [[ ! -d "${COCO_DIR}/.git" ]]; then
        git clone https://github.com/Tox1cfnbr7/coco.git "${COCO_DIR}/repo" >> "$LOG_FILE" 2>&1
    fi
    success "Repository cloned to ${COCO_DIR}/repo"
}

# ── Done ───────────────────────────────────────────────────
print_done() {
    echo ""
    echo -e "${GREEN}"
    cat << 'DONE'
  ────────────────────────────────────────────────
   COCO installation complete.
   A reboot is required to activate Proxmox VE.
  ────────────────────────────────────────────────
DONE
    echo -e "${RESET}"
    echo -e "  After reboot:"
    echo -e "  Proxmox GUI  :  ${CYAN}https://${COCO_IP}:8006${RESET}"
    echo -e "  COCO Web-GUI :  ${CYAN}http://${COCO_IP}:${COCO_PORT}${RESET}"
    echo -e "  Guacamole    :  ${CYAN}http://${COCO_IP}:8443${RESET}"
    echo -e "  Config       :  ${COCO_DIR}/.env"
    echo -e "  Logs         :  ${LOG_FILE}"
    echo ""
    divider
    read -rp "  Reboot now? [y/N]: " reboot_now
    if [[ "${reboot_now,,}" == "y" ]]; then
        info "Rebooting..."
        reboot
    else
        warn "Remember to reboot before using Proxmox VE."
    fi
    echo ""
}

# ── Main ───────────────────────────────────────────────────
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    print_logo
    check_root
    check_os
    collect_config
    install_proxmox
    configure_system
    install_docker
    install_ansible
    install_packer
    setup_coco
    print_done
}

main "$@"
