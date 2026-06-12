#!/usr/bin/env bash
# ============================================================
#   COCO - Attack & Defense Platform
#   Installer v0.5.0
#   Target: Debian 13 (Trixie) + Proxmox VE 9
#   Stack: FastAPI + React + PostgreSQL + Redis (native, no Docker)
# ============================================================

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

COCO_VERSION="0.6.0"
COCO_DIR="/opt/coco"
LOG_FILE="/var/log/coco-install.log"
STATE_FILE="/var/lib/coco-install.state"
COCO_SERVICE="/etc/systemd/system/coco-install-resume.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

log()     { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }
info()    { echo -e "${CYAN}  [*]${RESET} $*"; log "INFO: $*"; }
success() { echo -e "${GREEN}  [+]${RESET} $*"; log "OK:   $*"; }
warn()    { echo -e "${YELLOW}  [!]${RESET} $*"; log "WARN: $*"; }
error()   { echo -e "${RED}  [-] $*${RESET}"; log "ERR:  $*"; exit 1; }
step()    { echo ""; echo -e "  ${BOLD}${CYAN}>> $*${RESET}"; echo ""; }
divider() { echo -e "  ${DIM}────────────────────────────────────────────────${RESET}"; }

# ── State management ───────────────────────────────────────
save_state() { echo "$1" > "$STATE_FILE"; log "STATE: $1"; }
get_state()  { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "start"; }
done_state() { local s; s=$(get_state); [[ "$s" == "$1" || "$s" > "$1" ]]; }

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
    echo -e "  ${BOLD}Version${RESET}  ${COCO_VERSION}  |  ${BOLD}Target${RESET}  Debian 13 + Proxmox VE 9"
    echo -e "  ${BOLD}Log${RESET}      ${LOG_FILE}"
    divider
    echo ""
}

# ── Checks ─────────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || error "Run as root: sudo bash install.sh"
}

check_os() {
    step "System check"
    [[ -f /etc/debian_version ]] || error "Requires Debian 13."
    success "OS: Debian $(cat /etc/debian_version)"

    local ram_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    [[ $ram_gb -lt 8 ]] && warn "RAM: ${ram_gb} GB — recommended 16+ GB" \
        || success "RAM: ${ram_gb} GB"

    local disk_gb
    disk_gb=$(df / --output=avail -BG | tail -1 | tr -d 'G ')
    [[ $disk_gb -lt 50 ]] && error "Disk: only ${disk_gb} GB free — need 50+ GB" \
        || success "Disk: ${disk_gb} GB free"

    if grep -qE 'vmx|svm' /proc/cpuinfo; then
        success "CPU: Nested virtualization flags present (vmx/svm)"
    else
        warn "CPU: No vmx/svm flags — set Proxmox CPU type to 'host'"
    fi
}

# ── Config ─────────────────────────────────────────────────
collect_config() {
    step "Configuration"
    echo -e "  ${DIM}Press Enter to accept defaults.${RESET}"
    echo ""

    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')
    local detected_hostname
    detected_hostname=$(hostname)

    read -rp "  $(echo -e "${BOLD}COCO VM IP${RESET}") [${detected_ip}]: " COCO_IP
    COCO_IP=${COCO_IP:-$detected_ip}

    read -rp "  $(echo -e "${BOLD}Proxmox hostname${RESET}") [${detected_hostname}]: " PVE_HOSTNAME
    PVE_HOSTNAME=${PVE_HOSTNAME:-$detected_hostname}

    read -rsp "  $(echo -e "${BOLD}Root password (for Proxmox GUI login)${RESET}"): " PVE_ROOT_PASSWORD
    echo ""
    read -rsp "  $(echo -e "${BOLD}Confirm password${RESET}"): " PVE_ROOT_PASSWORD_CONFIRM
    echo ""

    [[ "$PVE_ROOT_PASSWORD" == "$PVE_ROOT_PASSWORD_CONFIRM" ]] \
        || error "Passwords do not match."
    [[ ${#PVE_ROOT_PASSWORD} -ge 8 ]] \
        || error "Password must be at least 8 characters."

    echo ""
    read -rp "  $(echo -e "${BOLD}COCO admin email${RESET}") [admin@coco.local]: " COCO_ADMIN_EMAIL
    COCO_ADMIN_EMAIL=${COCO_ADMIN_EMAIL:-admin@coco.local}

    read -rsp "  $(echo -e "${BOLD}COCO admin password${RESET}") (min 10 chars): " COCO_ADMIN_PASSWORD
    echo ""
    [[ ${#COCO_ADMIN_PASSWORD} -ge 10 ]] || error "Admin password must be at least 10 characters."

    SECRET_KEY=$(openssl rand -hex 32)

    echo ""
    step "Summary"
    divider
    echo -e "  Proxmox GUI  :  ${CYAN}https://${COCO_IP}:8006${RESET}"
    echo -e "  COCO Web-GUI :  ${CYAN}https://${COCO_IP}:443${RESET}"
    echo -e "  Hostname     :  ${PVE_HOSTNAME}"
    echo -e "  Install dir  :  ${COCO_DIR}"
    divider
    echo ""
    read -rp "  Proceed with installation? [y/N]: " confirm
    [[ "${confirm,,}" == "y" ]] || error "Installation cancelled."

    # Save config for post-reboot resume
    mkdir -p "${COCO_DIR}"
    cat > "${COCO_DIR}/.install-config" << CFGEOF
COCO_IP="${COCO_IP}"
PVE_HOSTNAME="${PVE_HOSTNAME}"
PVE_ROOT_PASSWORD="${PVE_ROOT_PASSWORD}"
COCO_ADMIN_EMAIL="${COCO_ADMIN_EMAIL}"
COCO_ADMIN_PASSWORD="${COCO_ADMIN_PASSWORD}"
SECRET_KEY="${SECRET_KEY}"
CFGEOF
    chmod 600 "${COCO_DIR}/.install-config"
}

load_config() {
    [[ -f "${COCO_DIR}/.install-config" ]] \
        || error "Config file not found. Run install.sh from scratch."
    source "${COCO_DIR}/.install-config"
}

# ── Bootstrap ──────────────────────────────────────────────
install_bootstrap() {
    done_state "bootstrap" && { success "Bootstrap: already done"; return; }
    step "Installing bootstrap dependencies"

    apt-get update -qq >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget git vim unzip jq openssl \
        ca-certificates gnupg lsb-release \
        procps iproute2 net-tools \
        python3 python3-pip python3-venv \
        >> "$LOG_FILE" 2>&1
    success "Bootstrap dependencies installed"
    save_state "bootstrap"
}

# ── Proxmox VE ─────────────────────────────────────────────
install_proxmox() {
    done_state "proxmox" && { success "Proxmox VE: already installed"; return; }
    step "Installing Proxmox VE 9"

    info "Setting hostname to ${PVE_HOSTNAME}..."
    hostnamectl set-hostname "${PVE_HOSTNAME}"
    cat > /etc/hosts << HOSTSEOF
127.0.0.1       localhost
${COCO_IP}      ${PVE_HOSTNAME}.local ${PVE_HOSTNAME}
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
HOSTSEOF
    success "Hostname set"

    info "Cleaning existing apt sources..."
    rm -f /etc/apt/sources.list.d/pve-install-repo.list
    rm -f /etc/apt/sources.list.d/pve-install-repo.sources
    rm -f /etc/apt/sources.list.d/pve-enterprise.list
    rm -f /etc/apt/sources.list.d/ceph.list
    rm -f /etc/apt/trusted.gpg.d/proxmox-*.gpg
    rm -f /usr/share/keyrings/proxmox-*.gpg
    success "Old sources cleaned"

    info "Downloading Proxmox GPG key..."
    wget --no-check-certificate -q \
        https://download.proxmox.com/debian/proxmox-release-trixie.gpg \
        -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg \
        >> "$LOG_FILE" 2>&1
    success "GPG key installed"

    info "Adding Proxmox VE repository..."
    cat > /etc/apt/sources.list.d/pve-install-repo.sources << REPOEOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
REPOEOF
    success "Repository configured"

    info "Updating system..."
    apt-get update -qq >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq >> "$LOG_FILE" 2>&1
    success "System up to date"

    info "Installing Proxmox VE kernel..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-default-kernel \
        >> "$LOG_FILE" 2>&1
    success "Proxmox kernel installed"

    info "Installing Proxmox VE packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        proxmox-ve postfix open-iscsi chrony \
        >> "$LOG_FILE" 2>&1
    success "Proxmox VE installed"

    info "Setting root password..."
    echo -e "${PVE_ROOT_PASSWORD}\n${PVE_ROOT_PASSWORD}" | passwd root \
        >> "$LOG_FILE" 2>&1
    success "Root password set"

    info "Removing Debian default kernel..."
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        linux-image-amd64 'linux-image-6.12*' >> "$LOG_FILE" 2>&1 || true
    success "Debian kernel removed"

    info "Updating GRUB..."
    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg >> "$LOG_FILE" 2>&1 || true
    fi
    success "GRUB updated — Proxmox kernel active after reboot"

    info "Removing os-prober..."
    apt-get remove -y os-prober >> "$LOG_FILE" 2>&1 || true
    success "os-prober removed"

    save_state "proxmox"
}

# ── Setup resume service ────────────────────────────────────
setup_resume_service() {
    info "Setting up post-reboot resume service..."

    # Script an fixen Ort kopieren damit es nach Reboot gefunden wird
    cp "$(realpath "$0")" "${COCO_DIR}/install.sh" 2>/dev/null || \
        cp "$0" "${COCO_DIR}/install.sh" 2>/dev/null || true
    chmod +x "${COCO_DIR}/install.sh"
    info "Installer copied to ${COCO_DIR}/install.sh"

    cat > "$COCO_SERVICE" << SVCEOF
[Unit]
Description=COCO Installer Resume
After=network-online.target
Wants=network-online.target
ConditionPathExists=${STATE_FILE}

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/bash ${COCO_DIR}/install.sh --resume
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable coco-install-resume.service >> "$LOG_FILE" 2>&1
    success "Resume service registered — will continue after reboot"
}

remove_resume_service() {
    if [[ -f "$COCO_SERVICE" ]]; then
        systemctl disable coco-install-resume.service >> "$LOG_FILE" 2>&1 || true
        rm -f "$COCO_SERVICE"
        systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
    fi
}

# ── Reboot checkpoint ──────────────────────────────────────
reboot_for_kernel() {
    done_state "rebooted" && { success "Kernel reboot: already done"; return; }

    info "Copying installer to permanent location..."
    cp "$(realpath "$0")" "${COCO_DIR}/install.sh"
    chmod +x "${COCO_DIR}/install.sh"
    success "Installer saved to ${COCO_DIR}/install.sh"

    setup_resume_service

    echo ""
    echo -e "${YELLOW}"
    cat << 'RBT'
  ────────────────────────────────────────────────
   Reboot required to activate Proxmox VE kernel.
   Installation will resume automatically.
   Watch progress: journalctl -fu coco-install-resume
  ────────────────────────────────────────────────
RBT
    echo -e "${RESET}"
    save_state "rebooted"
    info "Rebooting in 5 seconds..."
    sleep 5
    reboot
    exit 0
}

# ── Post-reboot: system config ─────────────────────────────
configure_system() {
    done_state "sysconfig" && { success "System config: already done"; return; }
    step "Configuring system"

    local kernel
    kernel=$(uname -r)
    info "Running kernel: ${kernel}"

    if [[ "$kernel" != *"pve"* ]]; then
        warn "Not running Proxmox kernel yet (${kernel}) — may need another reboot"
    else
        success "Proxmox kernel active: ${kernel}"
    fi

    info "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1"   > /etc/sysctl.d/99-coco.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-coco.conf
    sysctl -p /etc/sysctl.d/99-coco.conf >> "$LOG_FILE" 2>&1
    success "IP forwarding enabled"

    save_state "sysconfig"
}

# ── Python / FastAPI backend ───────────────────────────────
install_backend() {
    done_state "backend" && { success "Backend: already installed"; return; }
    step "Installing Python + FastAPI backend"

    info "Installing Python packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        python3 python3-pip python3-venv python3-dev \
        build-essential libssl-dev libffi-dev \
        >> "$LOG_FILE" 2>&1
    success "Python installed: $(python3 --version)"

    info "Creating COCO Python venv..."
    python3 -m venv "${COCO_DIR}/venv" >> "$LOG_FILE" 2>&1
    "${COCO_DIR}/venv/bin/pip" install --quiet --upgrade pip >> "$LOG_FILE" 2>&1

    info "Installing Python dependencies from requirements.txt..."
    if [[ -f "${COCO_DIR}/repo/web/backend/requirements.txt" ]]; then
        "${COCO_DIR}/venv/bin/pip" install --quiet \
            -r "${COCO_DIR}/repo/web/backend/requirements.txt" \
            >> "$LOG_FILE" 2>&1
    else
        "${COCO_DIR}/venv/bin/pip" install --quiet \
            fastapi "uvicorn[standard]" \
            sqlalchemy alembic psycopg2-binary \
            "python-jose[cryptography]" "passlib[bcrypt]" \
            python-multipart httpx pydantic-settings \
            redis slowapi python-dotenv \
            >> "$LOG_FILE" 2>&1
    fi
    success "FastAPI + dependencies installed"

    save_state "backend"
}

# ── PostgreSQL ─────────────────────────────────────────────
install_postgres() {
    done_state "postgres" && { success "PostgreSQL: already installed"; return; }
    step "Installing PostgreSQL"

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        postgresql postgresql-client \
        >> "$LOG_FILE" 2>&1
    systemctl enable --now postgresql >> "$LOG_FILE" 2>&1

    info "Creating COCO database and user..."
    local db_pass
    db_pass=$(openssl rand -hex 16)
    sudo -u postgres psql -c "CREATE USER coco WITH PASSWORD '${db_pass}';" \
        >> "$LOG_FILE" 2>&1 || true
    sudo -u postgres psql -c "CREATE DATABASE coco OWNER coco;" \
        >> "$LOG_FILE" 2>&1 || true

    echo "DB_URL=postgresql://coco:${db_pass}@localhost/coco" \
        >> "${COCO_DIR}/.env"
    echo "DATABASE_URL=postgresql://coco:${db_pass}@localhost/coco" \
        >> "${COCO_DIR}/.env"
    echo "REDIS_URL=redis://localhost:6379" \
        >> "${COCO_DIR}/.env"
    success "PostgreSQL ready — database: coco"

    save_state "postgres"
}

# ── Redis ──────────────────────────────────────────────────
install_redis() {
    done_state "redis" && { success "Redis: already installed"; return; }
    step "Installing Redis"

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server \
        >> "$LOG_FILE" 2>&1
    systemctl enable --now redis-server >> "$LOG_FILE" 2>&1
    success "Redis running"

    save_state "redis"
}

# ── Guacamole ──────────────────────────────────────────────
install_guacamole() {
    done_state "guacamole" && { success "Guacamole: already installed"; return; }
    step "Installing Apache Guacamole (browser-based terminal)"

    local GUAC_VER="1.5.5"
    local GUAC_URL="https://downloads.apache.org/guacamole/${GUAC_VER}/source/guacamole-server-${GUAC_VER}.tar.gz"

    info "Installing build dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        build-essential libcairo2-dev libjpeg62-turbo-dev libpng-dev \
        libtool-bin libossp-uuid-dev libavcodec-dev libavformat-dev \
        libavutil-dev libswscale-dev freerdp2-dev libpango1.0-dev \
        libssh2-1-dev libtelnet-dev libvncserver-dev libwebsockets-dev \
        libpulse-dev libssl-dev libvorbis-dev libwebp-dev \
        tomcat10 tomcat10-admin \
        >> "$LOG_FILE" 2>&1
    success "Build dependencies installed"

    info "Downloading guacamole-server ${GUAC_VER}..."
    wget -q "${GUAC_URL}" -O /tmp/guacamole-server.tar.gz >> "$LOG_FILE" 2>&1
    tar -xzf /tmp/guacamole-server.tar.gz -C /tmp >> "$LOG_FILE" 2>&1

    info "Compiling guacd (this takes a few minutes)..."
    cd "/tmp/guacamole-server-${GUAC_VER}"
    ./configure --with-init-dir=/etc/init.d >> "$LOG_FILE" 2>&1
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    ldconfig >> "$LOG_FILE" 2>&1
    cd /
    rm -rf /tmp/guacamole-server*
    success "guacd compiled and installed"

    info "Downloading Guacamole web app..."
    local WAR_URL="https://downloads.apache.org/guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war"
    wget -q "${WAR_URL}" -O /var/lib/tomcat10/webapps/guacamole.war >> "$LOG_FILE" 2>&1
    success "Guacamole WAR deployed to Tomcat"

    info "Configuring Guacamole..."
    mkdir -p /etc/guacamole/{extensions,lib}
    mkdir -p /usr/share/tomcat10/.guacamole

    # Main config
    cat > /etc/guacamole/guacamole.properties << GUACPROP
guacd-hostname: localhost
guacd-port: 4822
auth-provider: net.sourceforge.guacamole.net.basic.BasicFileAuthenticationProvider
basic-user-mapping: /etc/guacamole/user-mapping.xml
GUACPROP

    # Symlink for Tomcat
    ln -sf /etc/guacamole /usr/share/tomcat10/.guacamole

    # Generate guacd user mapping — will be updated dynamically by COCO
    cat > /etc/guacamole/user-mapping.xml << 'GUACXML'
<user-mapping>
    <authorize username="coco" password="coco_guac_placeholder">
    </authorize>
</user-mapping>
GUACXML

    chmod 640 /etc/guacamole/user-mapping.xml
    chown root:tomcat /etc/guacamole/user-mapping.xml

    info "Enabling guacd and Tomcat services..."
    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable --now guacd >> "$LOG_FILE" 2>&1
    systemctl enable --now tomcat10 >> "$LOG_FILE" 2>&1

    # Save guac token to env
    local guac_pass
    guac_pass=$(openssl rand -hex 16)
    echo "GUACAMOLE_URL=http://localhost:8080/guacamole" >> "${COCO_DIR}/.env"
    echo "GUACAMOLE_PASS=${guac_pass}" >> "${COCO_DIR}/.env"

    success "Guacamole running at http://localhost:8080/guacamole"
    success "Access via COCO proxy at https://${COCO_IP}/terminal"

    save_state "guacamole"
}


install_ansible() {
    done_state "ansible" && { success "Ansible: already installed"; return; }
    step "Installing Ansible"

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        ansible ansible-core \
        >> "$LOG_FILE" 2>&1
    success "Ansible: $(ansible --version | head -1)"

    save_state "ansible"
}

# ── Packer ─────────────────────────────────────────────────
install_packer() {
    done_state "packer" && { success "Packer: already installed"; return; }
    step "Installing Packer"

    local PACKER_VER="1.11.0"
    wget -q \
        "https://releases.hashicorp.com/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip" \
        -O /tmp/packer.zip >> "$LOG_FILE" 2>&1
    unzip -q /tmp/packer.zip -d /usr/local/bin/
    rm -f /tmp/packer.zip
    chmod +x /usr/local/bin/packer
    success "Packer: $(packer --version)"

    save_state "packer"
}

# ── Node.js ────────────────────────────────────────────────
install_node() {
    done_state "node" && { success "Node.js: already installed"; return; }
    step "Installing Node.js"

    info "Adding Node.js 22 LTS repository..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >> "$LOG_FILE" 2>&1
    success "Node.js: $(node --version)  npm: $(npm --version)"

    save_state "node"
}

# ── Frontend build ──────────────────────────────────────────
build_frontend() {
    done_state "frontend" && { success "Frontend: already built"; return; }
    step "Building React frontend"

    local frontend_dir="${COCO_DIR}/repo/web/frontend"

    if [[ ! -d "$frontend_dir" ]]; then
        warn "Frontend source not found at ${frontend_dir} — skipping build"
        return
    fi

    info "Installing npm dependencies..."
    cd "$frontend_dir"
    npm install --silent >> "$LOG_FILE" 2>&1
    success "npm packages installed"

    info "Building production bundle..."
    npm run build >> "$LOG_FILE" 2>&1
    success "Frontend built → ${frontend_dir}/dist"

    save_state "frontend"
}

# ── Deploy COCO service ─────────────────────────────────────
deploy_service() {
    done_state "service" && { success "COCO service: already deployed"; return; }
    step "Deploying COCO systemd service"

    local service_src="${COCO_DIR}/repo/web/backend/coco.service"

    if [[ -f "$service_src" ]]; then
        cp "$service_src" /etc/systemd/system/coco.service
    else
        cat > /etc/systemd/system/coco.service << SVCEOF
[Unit]
Description=COCO Attack & Defense Platform
After=network.target postgresql.service redis.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=${COCO_DIR}/repo/web/backend
ExecStart=${COCO_DIR}/venv/bin/uvicorn main:app \\
    --host 0.0.0.0 \\
    --port 443 \\
    --ssl-certfile ${COCO_DIR}/ssl/coco.crt \\
    --ssl-keyfile ${COCO_DIR}/ssl/coco.key \\
    --workers 4 \\
    --access-log \\
    --log-level info
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONPATH=${COCO_DIR}/repo/web/backend

[Install]
WantedBy=multi-user.target
SVCEOF
    fi

    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable coco >> "$LOG_FILE" 2>&1
    systemctl start coco >> "$LOG_FILE" 2>&1 || true

    sleep 2
    if systemctl is-active --quiet coco; then
        success "COCO service running on port 443"
    else
        warn "COCO service failed to start — check: journalctl -xeu coco"
    fi

    save_state "service"
}
# ── DB Schema init ─────────────────────────────────────────
init_database() {
    done_state "dbinit" && { success "Database schema: already initialized"; return; }
    step "Initializing database schema"

    info "Creating tables..."
    PYTHONPATH="${COCO_DIR}/repo/web/backend" \
    "${COCO_DIR}/venv/bin/python3" << 'PYEOF'
import sys
sys.path.insert(0, '/opt/coco/repo/web/backend')
from core.database import engine, Base
from models.user import User
from models.game import Game, Team, VM, GameEvent, AuditLog
Base.metadata.create_all(bind=engine)
print("Tables created.")
PYEOF
    success "Database schema initialized"
    save_state "dbinit"
}

# ── Create admin user ──────────────────────────────────────
create_admin() {
    done_state "admin" && { success "Admin user: already created"; return; }
    step "Creating admin user"

    info "Creating admin: ${COCO_ADMIN_EMAIL}..."
    PYTHONPATH="${COCO_DIR}/repo/web/backend" \
    "${COCO_DIR}/venv/bin/python3" << PYEOF
import sys
sys.path.insert(0, '/opt/coco/repo/web/backend')
from core.database import SessionLocal
from core.security import hash_password
from models.user import User, UserRole
db = SessionLocal()
existing = db.query(User).filter(User.email == '${COCO_ADMIN_EMAIL}').first()
if existing:
    print("Admin already exists.")
else:
    admin = User(
        email='${COCO_ADMIN_EMAIL}',
        username='admin',
        hashed_password=hash_password('${COCO_ADMIN_PASSWORD}'),
        role=UserRole.admin,
        is_active=True,
    )
    db.add(admin)
    db.commit()
    print("Admin created.")
db.close()
PYEOF
    success "Admin user ready: ${COCO_ADMIN_EMAIL}"
    save_state "admin"
}

# ── SSL Certificate ────────────────────────────────────────
setup_ssl() {
    done_state "ssl" && { success "SSL: already configured"; return; }
    step "Generating SSL certificate"

    mkdir -p "${COCO_DIR}/ssl"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${COCO_DIR}/ssl/coco.key" \
        -out "${COCO_DIR}/ssl/coco.crt" \
        -subj "/C=CH/ST=COCO/L=COCO/O=COCO/CN=${COCO_IP}" \
        >> "$LOG_FILE" 2>&1
    chmod 600 "${COCO_DIR}/ssl/coco.key"
    success "SSL certificate generated (self-signed, 365 days)"

    save_state "ssl"
}

# ── COCO directories + env ─────────────────────────────────
setup_coco() {
    done_state "coco" && { success "COCO dirs: already set up"; return; }
    step "Setting up COCO"

    mkdir -p "${COCO_DIR}"/{backend,frontend,ansible,packer,ssl,logs}

    cat > "${COCO_DIR}/.env" << ENVEOF
# COCO Environment — generated $(date)
SECRET_KEY=${SECRET_KEY}
COCO_IP=${COCO_IP}
COCO_PORT=443
PVE_HOSTNAME=${PVE_HOSTNAME}
PVE_NODE=${PVE_HOSTNAME}
PROXMOX_HOST=${COCO_IP}
PROXMOX_USER=root@pam
PROXMOX_PASSWORD=${PVE_ROOT_PASSWORD}
PROXMOX_NODE=${PVE_HOSTNAME}
COCO_REPO_DIR=${COCO_DIR}/repo
SSL_CERT=${COCO_DIR}/ssl/coco.crt
SSL_KEY=${COCO_DIR}/ssl/coco.key
ENVEOF
    chmod 600 "${COCO_DIR}/.env"
    success "Environment config written"

    info "Cloning COCO repository..."
    if [[ ! -d "${COCO_DIR}/repo/.git" ]]; then
        git clone https://github.com/Tox1cfnbr7/coco.git \
            "${COCO_DIR}/repo" >> "$LOG_FILE" 2>&1
    else
        info "Repo already cloned — pulling latest..."
        git -C "${COCO_DIR}/repo" pull >> "$LOG_FILE" 2>&1
    fi
    success "Repository ready at ${COCO_DIR}/repo"

    save_state "coco"
}

# ── Done ───────────────────────────────────────────────────
print_done() {
    remove_resume_service
    rm -f "${COCO_DIR}/.install-config"
    save_state "complete"

    echo ""
    echo -e "${GREEN}"
    cat << 'DONE'
  ────────────────────────────────────────────────
   COCO installation complete.
  ────────────────────────────────────────────────
DONE
    echo -e "${RESET}"
    echo -e "  ${BOLD}COCO Web-GUI${RESET}  :  ${CYAN}https://${COCO_IP}${RESET}"
    echo -e "  ${BOLD}Proxmox GUI${RESET}   :  ${CYAN}https://${COCO_IP}:8006${RESET}"
    echo ""
    echo -e "  ${BOLD}Admin login${RESET}"
    echo -e "  Email     :  ${COCO_ADMIN_EMAIL}"
    echo -e "  Password  :  (the one you set during install)"
    echo ""
    echo -e "  ${BOLD}Service${RESET}       :  systemctl status coco"
    echo -e "  ${BOLD}Logs${RESET}          :  journalctl -xeu coco"
    echo -e "  ${BOLD}Config${RESET}        :  ${COCO_DIR}/.env"
    echo ""
    divider
    echo ""
}

# ── Main flow ──────────────────────────────────────────────
run_all() {
    install_bootstrap
    install_proxmox
    reboot_for_kernel
    configure_system
    setup_coco
    install_backend
    install_postgres
    install_redis
    install_guacamole
    install_ansible
    install_packer
    install_node
    setup_ssl
    build_frontend
    init_database
    create_admin
    deploy_service
    print_done
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "${COCO_DIR}"
    print_logo

    if [[ "${1:-}" == "--resume" ]]; then
        info "Resuming after reboot..."
        load_config
        run_all
        return
    fi

    check_root
    check_os
    collect_config
    run_all
}

main "${@}"
