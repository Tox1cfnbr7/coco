#!/usr/bin/env bash
# ============================================================
#   COCO - Attack & Defense Platform
#   Installer v0.9.3
#   Target:  Debian 13 (Trixie) + Proxmox VE 9
#   Stack:   FastAPI + React + PostgreSQL + Redis + Guacamole
#   Repo:    https://github.com/Tox1cfnbr7/coco
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ── Versioning ─────────────────────────────────────────────
COCO_INSTALLER_VERSION="0.9.7"
COCO_APP_VERSION="${COCO_APP_VERSION:-0.9.7}"
COCO_REPO_URL="${COCO_REPO_URL:-https://github.com/Tox1cfnbr7/coco.git}"
COCO_REPO_BRANCH="${COCO_REPO_BRANCH:-main}"
COCO_INSTALLER_RAW_URL="${COCO_INSTALLER_RAW_URL:-https://raw.githubusercontent.com/Tox1cfnbr7/coco/main/scripts/install.sh}"

# ── Paths ──────────────────────────────────────────────────
COCO_DIR="${COCO_DIR:-/opt/coco}"
COCO_REPO_DIR="${COCO_DIR}/repo"
COCO_VENV_DIR="${COCO_DIR}/venv"
COCO_SSL_DIR="${COCO_DIR}/ssl"
COCO_ENV_FILE="${COCO_DIR}/.env"
COCO_CONFIG_FILE="${COCO_DIR}/.install-config"
COCO_VERSION_FILE="${COCO_DIR}/VERSION"

LOG_DIR="${LOG_DIR:-/var/log/coco}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/install.log}"
STATE_DIR="${STATE_DIR:-/var/lib/coco-install}"
STEP_DIR="${STATE_DIR}/steps"
CURRENT_STEP_FILE="${STATE_DIR}/current.step"
STATE_FILE="${STATE_DIR}/state"
COCO_RESUME_SERVICE="/etc/systemd/system/coco-install-resume.service"

# ── Tool versions ──────────────────────────────────────────
PACKER_VERSION="${PACKER_VERSION:-1.11.0}"
NODE_MAJOR="${NODE_MAJOR:-22}"
GUAC_VERSION="${GUAC_VERSION:-1.6.0}"
# COCO mainly needs Guacamole for browser-based SSH/terminal access.
# RDP build on Debian 13 currently fails with FreeRDP 3.x deprecation warnings
# treated as errors in guacamole-server 1.6.0. Keep RDP disabled by default.
COCO_GUAC_ENABLE_RDP="${COCO_GUAC_ENABLE_RDP:-0}"

# ── Flags ──────────────────────────────────────────────────
VERBOSE=0
ASSUME_YES=0
RESUME=0
NO_REBOOT=0

# ── Install steps ──────────────────────────────────────────
INSTALL_STEPS=(
  bootstrap
  proxmox
  kernel_reboot
  sysconfig
  coco
  backend
  postgres
  redis
  guacamole
  ansible
  packer
  node
  ssl
  frontend
  dbinit
  admin
  service
)
TOTAL_STEPS="${#INSTALL_STEPS[@]}"

# ── Colors ─────────────────────────────────────────────────
if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ── Logging ────────────────────────────────────────────────
timestamp()    { date '+%Y-%m-%d %H:%M:%S'; }
log_line()     { local lvl="$1"; shift; printf '%s [%s] %s\n' "$(timestamp)" "$lvl" "$*" >> "$LOG_FILE"; }
info()         { printf '%b  [*]%b %s\n' "$CYAN"   "$RESET" "$*"; log_line "INFO" "$*"; }
success()      { printf '%b  [+]%b %s\n' "$GREEN"  "$RESET" "$*"; log_line "OK"   "$*"; }
warn()         { printf '%b  [!]%b %s\n' "$YELLOW" "$RESET" "$*"; log_line "WARN" "$*"; }
fail()         { printf '%b  [-] %s%b\n' "$RED"    "$*" "$RESET"; log_line "ERR"  "$*"; exit 1; }
section()      { echo ""; printf '  %b>> %s%b\n' "${BOLD}${CYAN}" "$*" "$RESET"; echo ""; log_line "STEP" "$*"; }
divider()      { printf '  %b────────────────────────────────────────────────%b\n' "$DIM" "$RESET"; }

ensure_runtime_dirs() {
  mkdir -p "$COCO_DIR" "$COCO_SSL_DIR" "$LOG_DIR" "$STATE_DIR" "$STEP_DIR"
  chmod 0755 "$COCO_DIR" "$COCO_SSL_DIR" "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
  chmod 0700 "$STEP_DIR" 2>/dev/null || true
  touch "$LOG_FILE"
  chmod 0600 "$LOG_FILE" 2>/dev/null || true
}

print_log_tail() {
  if [[ -f "$LOG_FILE" ]]; then
    echo ""
    printf '  %bLast 30 log lines from %s:%b\n' "$DIM" "$LOG_FILE" "$RESET"
    tail -n 30 "$LOG_FILE" || true
  fi
}

run_cmd() {
  local msg="$1"; shift
  info "$msg"
  log_line "RUN" "$(printf '%q ' "$@")"
  local rc=0
  set +e
  if [[ "$VERBOSE" == "1" ]]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"; rc=${PIPESTATUS[0]}
  else
    "$@" >> "$LOG_FILE" 2>&1; rc=$?
  fi
  set -e
  if [[ $rc -eq 0 ]]; then
    success "$msg"
  else
    warn "$msg failed (exit $rc)"
    print_log_tail
    exit "$rc"
  fi
}

run_cmd_allow_fail() {
  local msg="$1"; shift
  info "$msg"
  set +e; "$@" >> "$LOG_FILE" 2>&1; local rc=$?; set -e
  if [[ $rc -eq 0 ]]; then success "$msg"; else warn "$msg returned $rc; continuing"; fi
}

on_error() {
  local rc=$? line="${BASH_LINENO[0]:-?}" cmd="${BASH_COMMAND:-?}"
  local current="unknown"
  [[ -f "$CURRENT_STEP_FILE" ]] && current="$(cat "$CURRENT_STEP_FILE" 2>/dev/null || echo unknown)"
  log_line "FATAL" "line=$line rc=$rc step=$current cmd=$cmd"
  printf '\n%b  [-] Installer failed at line %s, step: %s%b\n' "$RED" "$line" "$current" "$RESET"
  print_log_tail
  exit "$rc"
}
trap on_error ERR

# ── Argument parsing ───────────────────────────────────────
usage() {
  cat <<USAGE
COCO installer v${COCO_INSTALLER_VERSION}

Usage: bash install.sh [options]

Options:
  --resume      Resume installation after reboot (used by systemd)
  --verbose     Print all command output to console
  -y, --yes     Skip confirmation prompt
  --no-reboot   Do not reboot automatically (for testing)
  --version     Print installer version
  -h, --help    Show this help
USAGE
}

parse_args() {
  VERBOSE="${COCO_VERBOSE:-0}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume)    RESUME=1 ;;
      --verbose)   VERBOSE=1 ;;
      -y|--yes)    ASSUME_YES=1 ;;
      --no-reboot) NO_REBOOT=1 ;;
      --version)   echo "$COCO_INSTALLER_VERSION"; exit 0 ;;
      -h|--help)   usage; exit 0 ;;
      *) fail "Unknown argument: $1" ;;
    esac
    shift
  done
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run as root: sudo bash install.sh"
}

is_systemd_available() {
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system || -d /etc/systemd/system ]]
}

repair_apt_keyring_permissions() {
  # apt on Debian 13 verifies repositories as the _apt user. Existing keyrings
  # from failed previous runs must be world-readable, otherwise apt-get update
  # only emits warnings and later package operations become unreliable.
  local f
  for f in \
    /usr/share/keyrings/proxmox-archive-keyring.gpg \
    /usr/share/keyrings/proxmox-release-trixie.gpg \
    /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg; do
    if [[ -f "$f" ]]; then
      chown root:root "$f" 2>/dev/null || true
      chmod 0644 "$f" 2>/dev/null || true
    fi
  done
}

# ── State management ───────────────────────────────────────
step_number() {
  local key="$1" i=1 s
  for s in "${INSTALL_STEPS[@]}"; do
    [[ "$s" == "$key" ]] && { echo "$i"; return 0; }
    i=$((i+1))
  done
  echo "?"
}

is_done()   { [[ -f "${STEP_DIR}/${1}.done" ]]; }
mark_done() {
  mkdir -p "$STEP_DIR"
  : > "${STEP_DIR}/${1}.done"
  echo "$1" > "$STATE_FILE"
  rm -f "${STEP_DIR}/${1}.failed" 2>/dev/null || true
  log_line "STATE" "done=$1"
}

completed_steps() {
  local count=0 s
  for s in "${INSTALL_STEPS[@]}"; do is_done "$s" && count=$((count+1)); done
  echo "$count"
}

progress_bar() {
  local done_count pct filled empty bar="" i
  done_count="$(completed_steps)"
  pct=$(( done_count * 100 / TOTAL_STEPS ))
  filled=$(( pct / 5 ))
  empty=$(( 20 - filled ))
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  printf '  %b[%s] %s%% — %s/%s steps%b\n' "$DIM" "$bar" "$pct" "$done_count" "$TOTAL_STEPS" "$RESET"
}

with_step() {
  local key="$1" title="$2" fn="$3"
  if is_done "$key"; then
    success "$title: already done"
    progress_bar
    return 0
  fi
  echo "$key" > "$CURRENT_STEP_FILE"
  section "$title"
  info "Step $(step_number "$key")/${TOTAL_STEPS}: $key"
  "$fn"
  mark_done "$key"
  success "$title complete"
  progress_bar
}

# ── Config helpers ─────────────────────────────────────────
backup_file() {
  local f="$1"
  if [[ -f "$f" && ! -f "${f}.coco.bak" ]]; then
    cp -a "$f" "${f}.coco.bak"
    log_line "BACKUP" "$f"
  fi
  return 0
}

shell_config_write() {
  local old_umask
  old_umask="$(umask)"
  umask 077
  {
    printf 'COCO_IP=%q\n'             "$COCO_IP"
    printf 'PVE_HOSTNAME=%q\n'        "$PVE_HOSTNAME"
    printf 'PVE_ROOT_PASSWORD=%q\n'   "$PVE_ROOT_PASSWORD"
    printf 'COCO_ADMIN_EMAIL=%q\n'    "$COCO_ADMIN_EMAIL"
    printf 'COCO_ADMIN_PASSWORD=%q\n' "$COCO_ADMIN_PASSWORD"
    printf 'SECRET_KEY=%q\n'          "$SECRET_KEY"
    printf 'COCO_APP_VERSION=%q\n'    "$COCO_APP_VERSION"
    printf 'COCO_REPO_URL=%q\n'       "$COCO_REPO_URL"
    printf 'COCO_REPO_BRANCH=%q\n'    "$COCO_REPO_BRANCH"
  } > "$COCO_CONFIG_FILE"
  chmod 600 "$COCO_CONFIG_FILE"
  umask "$old_umask"
}

load_install_config() {
  [[ -f "$COCO_CONFIG_FILE" ]] || fail "Config not found: $COCO_CONFIG_FILE — run the installer from scratch."
  set -a
  # shellcheck disable=SC1090
  source "$COCO_CONFIG_FILE"
  set +a
  info "Config loaded — resuming for ${COCO_IP}"
}

dotenv_quote() {
  local v="$1"
  v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; v="${v//$'\n'/\\n}"
  printf '"%s"' "$v"
}

env_set() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  touch "$COCO_ENV_FILE"
  grep -v -E "^${key}=" "$COCO_ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$key" "$(dotenv_quote "$value")" >> "$tmp"
  mv "$tmp" "$COCO_ENV_FILE"
  chmod 600 "$COCO_ENV_FILE"
}

env_get() {
  local key="$1" line
  [[ -f "$COCO_ENV_FILE" ]] || return 1
  line="$(grep -E "^${key}=" "$COCO_ENV_FILE" | tail -n1 || true)"
  [[ -n "$line" ]] || return 1
  line="${line#*=}"; line="${line%\"}"; line="${line#\"}"
  printf '%s' "$line"
}

load_env_file() {
  [[ -f "$COCO_ENV_FILE" ]] || fail "Missing env file: $COCO_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$COCO_ENV_FILE"
  set +a
}

# Detect backend/frontend dirs (supports both web/backend and backend layouts)
backend_dir() {
  if   [[ -d "$COCO_REPO_DIR/web/backend" ]]; then printf '%s' "$COCO_REPO_DIR/web/backend"
  elif [[ -d "$COCO_REPO_DIR/backend"     ]]; then printf '%s' "$COCO_REPO_DIR/backend"
  else printf '%s' "$COCO_REPO_DIR/web/backend"; fi
}

frontend_dir() {
  if   [[ -d "$COCO_REPO_DIR/web/frontend" ]]; then printf '%s' "$COCO_REPO_DIR/web/frontend"
  elif [[ -d "$COCO_REPO_DIR/frontend"     ]]; then printf '%s' "$COCO_REPO_DIR/frontend"
  else printf '%s' "$COCO_REPO_DIR/web/frontend"; fi
}

write_version_file() {
  local commit="unknown" old_umask
  [[ -d "$COCO_REPO_DIR/.git" ]] && commit="$(git -C "$COCO_REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  old_umask="$(umask)"
  umask 077
  cat > "$COCO_VERSION_FILE" <<EOF
COCO_INSTALLER_VERSION=${COCO_INSTALLER_VERSION}
COCO_APP_VERSION=${COCO_APP_VERSION}
COCO_REPO_URL=${COCO_REPO_URL}
COCO_REPO_BRANCH=${COCO_REPO_BRANCH}
COCO_REPO_COMMIT=${commit}
INSTALLED_AT=$(date -Is)
EOF
  chmod 600 "$COCO_VERSION_FILE"
  umask "$old_umask"
}

# ── Logo ───────────────────────────────────────────────────
print_logo() {
  clear 2>/dev/null || true
  printf '%b' "$CYAN"
  cat << 'LOGO'
  ██████╗  ██████╗  ██████╗  ██████╗
 ██╔════╝ ██╔═══██╗██╔════╝ ██╔═══██╗
 ██║      ██║   ██║██║      ██║   ██║
 ██║      ██║   ██║██║      ██║   ██║
 ╚██████╗ ╚██████╔╝╚██████╗ ╚██████╔╝
  ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝
         Attack & Defense Platform
LOGO
  printf '%b' "$RESET"
  printf '  Version : %s | App : %s\n' "$COCO_INSTALLER_VERSION" "$COCO_APP_VERSION"
  printf '  Target  : Debian 13 (Trixie) + Proxmox VE 9\n'
  printf '  Log     : %s\n' "$LOG_FILE"
  divider
  echo ""
}

# ── Preflight ──────────────────────────────────────────────
check_os() {
  section "System check"
  [[ -f /etc/os-release ]] || fail "Missing /etc/os-release — Debian 13 required."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "debian" ]] || fail "Unsupported OS: ${PRETTY_NAME:-unknown}. Debian 13 required."
  [[ "${VERSION_ID:-}" == "13" || "${VERSION_CODENAME:-}" == "trixie" ]] \
    || fail "Unsupported Debian version: ${PRETTY_NAME:-unknown}. Debian 13 (Trixie) required."
  success "OS: ${PRETTY_NAME:-Debian 13}"

  local ram_gb disk_gb
  ram_gb="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
  [[ "$ram_gb" -lt 8  ]] && fail "RAM: ${ram_gb} GB — minimum 8 GB required."
  [[ "$ram_gb" -lt 16 ]] && warn "RAM: ${ram_gb} GB — 16+ GB recommended." || success "RAM: ${ram_gb} GB"

  disk_gb="$(df / --output=avail -BG | tail -1 | tr -d 'G ')"
  [[ "$disk_gb" -lt 50  ]] && fail "Disk: ${disk_gb} GB free — minimum 50 GB required."
  [[ "$disk_gb" -lt 300 ]] && warn "Disk: ${disk_gb} GB free — 300+ GB recommended." || success "Disk: ${disk_gb} GB free"

  grep -qE 'vmx|svm' /proc/cpuinfo \
    && success "CPU: nested virtualization flags present (vmx/svm)" \
    || warn "CPU: no vmx/svm flags — set Proxmox CPU type to 'host'"
}

detected_primary_ip() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1 || true)"
  [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  printf '%s' "$ip"
}

collect_config() {
  section "Configuration"
  echo "  Press Enter to accept defaults."
  echo ""

  local detected_ip detected_hostname
  detected_ip="$(detected_primary_ip)"
  detected_hostname="$(hostname 2>/dev/null || echo coco)"

  read -rp "  COCO VM IP [${detected_ip}]: " COCO_IP
  COCO_IP="${COCO_IP:-$detected_ip}"
  [[ -n "$COCO_IP" ]] || fail "Could not detect IP — enter it manually."

  read -rp "  Proxmox hostname [${detected_hostname}]: " PVE_HOSTNAME
  PVE_HOSTNAME="${PVE_HOSTNAME:-$detected_hostname}"

  read -rsp "  Root password (Proxmox GUI login): " PVE_ROOT_PASSWORD; echo ""
  read -rsp "  Confirm root password: " PVE_ROOT_PASSWORD_CONFIRM; echo ""
  [[ "$PVE_ROOT_PASSWORD" == "$PVE_ROOT_PASSWORD_CONFIRM" ]] || fail "Passwords do not match."
  [[ ${#PVE_ROOT_PASSWORD} -ge 8 ]] || fail "Root password must be at least 8 characters."

  echo ""
  read -rp "  COCO admin email [admin@coco.local]: " COCO_ADMIN_EMAIL
  COCO_ADMIN_EMAIL="${COCO_ADMIN_EMAIL:-admin@coco.local}"
  [[ "$COCO_ADMIN_EMAIL" == *@* ]] || fail "Invalid email: $COCO_ADMIN_EMAIL"

  read -rsp "  COCO admin password (min 10 chars): " COCO_ADMIN_PASSWORD; echo ""
  [[ ${#COCO_ADMIN_PASSWORD} -ge 10 ]] || fail "Admin password must be at least 10 characters."

  SECRET_KEY="$(openssl rand -hex 32)"

  echo ""
  section "Summary"
  divider
  printf '  Proxmox GUI  :  https://%s:8006\n' "$COCO_IP"
  printf '  COCO Web-GUI :  https://%s\n'      "$COCO_IP"
  printf '  Hostname     :  %s\n'              "$PVE_HOSTNAME"
  printf '  Admin email  :  %s\n'              "$COCO_ADMIN_EMAIL"
  printf '  Install dir  :  %s\n'              "$COCO_DIR"
  printf '  Repo         :  %s (%s)\n'         "$COCO_REPO_URL" "$COCO_REPO_BRANCH"
  divider
  echo ""

  if [[ "$ASSUME_YES" != "1" ]]; then
    local confirm
    read -rp "  Proceed with installation? [y/N]: " confirm
    [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || fail "Installation cancelled."
  fi

  shell_config_write
  success "Configuration saved to $COCO_CONFIG_FILE"
}

# ── Step implementations ───────────────────────────────────

step_bootstrap() {
  repair_apt_keyring_permissions
  run_cmd_allow_fail "Finishing interrupted package configuration" dpkg --configure -a
  run_cmd "Updating package index" apt-get update -qq
  run_cmd "Installing bootstrap tools" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget git vim unzip jq openssl ca-certificates gnupg lsb-release \
    procps iproute2 net-tools util-linux debconf-utils \
    python3 python3-pip python3-venv python3-dev build-essential
}

step_proxmox() {
  info "Setting hostname to ${PVE_HOSTNAME}"
  hostnamectl set-hostname "$PVE_HOSTNAME"
  backup_file /etc/hosts
  cat > /etc/hosts <<EOF
127.0.0.1       localhost
${COCO_IP}      ${PVE_HOSTNAME}.local ${PVE_HOSTNAME}
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
  success "Hostname configured"

  info "Cleaning old Proxmox apt sources"
  rm -f /etc/apt/sources.list.d/pve-install-repo.{list,sources} \
        /etc/apt/sources.list.d/pve-enterprise.{list,sources} \
        /etc/apt/sources.list.d/proxmox.sources \
        /etc/apt/sources.list.d/ceph.{list,sources} \
        /etc/apt/trusted.gpg.d/proxmox-*.gpg \
        /usr/share/keyrings/proxmox-*.gpg \
        /usr/share/keyrings/proxmox-archive-keyring.gpg
  success "Old sources cleaned"

  mkdir -p /usr/share/keyrings
  # Trixie keyring — try enterprise URL first, fall back to download mirror
  local key_url_primary="https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
  local key_url_fallback="https://download.proxmox.com/debian/proxmox-release-trixie.gpg"
  local key_dest="/usr/share/keyrings/proxmox-archive-keyring.gpg"

  set +e
  wget --no-check-certificate -q "$key_url_primary" -O "$key_dest" >> "$LOG_FILE" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 || ! -s "$key_dest" ]]; then
    warn "Primary keyring download failed — trying fallback"
    run_cmd "Downloading Proxmox keyring (fallback)" wget --no-check-certificate -q \
      "$key_url_fallback" -O "$key_dest"
  else
    success "Proxmox GPG keyring downloaded"
  fi
  chown root:root "$key_dest"
  chmod 0644 "$key_dest"

  cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  success "Proxmox no-subscription repository configured"

  echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
  echo "postfix postfix/mailname string ${PVE_HOSTNAME}" | debconf-set-selections

  run_cmd "Updating package index" apt-get update -qq
  run_cmd "Upgrading base system" env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq
  run_cmd "Installing Proxmox VE kernel" env DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-default-kernel
  run_cmd "Installing Proxmox VE" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    proxmox-ve postfix open-iscsi chrony

  info "Setting root password"
  printf 'root:%s\n' "$PVE_ROOT_PASSWORD" | chpasswd >> "$LOG_FILE" 2>&1
  success "Root password set"

  run_cmd_allow_fail "Removing Debian default kernel" env DEBIAN_FRONTEND=noninteractive \
    apt-get remove -y linux-image-amd64 'linux-image-6.12*'
  run_cmd_allow_fail "Removing os-prober" apt-get remove -y os-prober

  if command -v update-grub >/dev/null 2>&1; then
    run_cmd_allow_fail "Updating GRUB" update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    run_cmd_allow_fail "Updating GRUB" grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

save_installer_for_resume() {
  mkdir -p "$COCO_DIR"
  local src="${BASH_SOURCE[0]:-}"
  if [[ -f "$src" && "$(basename "$src")" != "bash" ]]; then
    install -m 0700 "$src" "${COCO_DIR}/install.sh"
    success "Installer saved to ${COCO_DIR}/install.sh"
    return 0
  fi
  warn "Installer source not available — downloading for resume"
  run_cmd "Downloading installer for resume" \
    curl -fsSL "$COCO_INSTALLER_RAW_URL" -o "${COCO_DIR}/install.sh"
  chmod 0700 "${COCO_DIR}/install.sh"
}

setup_resume_service() {
  is_systemd_available || fail "systemd required for post-reboot resume."
  save_installer_for_resume

  local flags="--resume"
  [[ "$VERBOSE" == "1" ]] && flags="$flags --verbose"

  cat > "$COCO_RESUME_SERVICE" <<EOF
[Unit]
Description=COCO Installer Resume
After=network-online.target
Wants=network-online.target
ConditionPathExists=${COCO_CONFIG_FILE}

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/bash ${COCO_DIR}/install.sh ${flags}
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=7200

[Install]
WantedBy=multi-user.target
EOF
  run_cmd "Reloading systemd" systemctl daemon-reload
  run_cmd "Enabling resume service" systemctl enable coco-install-resume.service
  success "Resume service registered"
}

step_kernel_reboot() {
  local kernel
  kernel="$(uname -r)"
  if [[ "$kernel" == *pve* ]]; then
    success "Proxmox kernel already active: $kernel"
    return 0
  fi

  setup_resume_service

  echo ""
  printf '%b  [!] Reboot required to activate Proxmox VE kernel.%b\n' "$YELLOW" "$RESET"
  echo "      Installation resumes AUTOMATICALLY after reboot."
  echo "      Watch live progress:  journalctl -fu coco-install-resume"
  echo "      Full log:             $LOG_FILE"
  echo ""

  if [[ "$NO_REBOOT" == "1" ]]; then
    warn "--no-reboot set. Reboot manually, then run: bash ${COCO_DIR}/install.sh --resume"
    exit 0
  fi

  mark_done "kernel_reboot"
  sync
  info "Rebooting in 5 seconds..."
  sleep 5
  systemctl reboot
  exit 0
}

step_sysconfig() {
  local kernel
  kernel="$(uname -r)"
  if [[ "$kernel" == *pve* ]]; then
    success "Proxmox kernel active: $kernel"
  else
    warn "Proxmox kernel not yet active (current: $kernel) — continuing anyway"
  fi

  cat > /etc/sysctl.d/99-coco.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
  run_cmd "Applying sysctl" sysctl -p /etc/sysctl.d/99-coco.conf
}


write_fallback_requirements() {
  local req="$1"
  mkdir -p "$(dirname "$req")"
  cat > "$req" <<'REQEOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.35
alembic==1.13.3
psycopg2-binary>=2.9.12
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
bcrypt==4.0.1
python-multipart==0.0.9
pydantic-settings==2.5.2
httpx==0.27.2
redis==5.1.0
slowapi==0.1.9
python-dotenv==1.0.1
REQEOF
}

normalise_requirements() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    warn "requirements.txt not found — writing known-good fallback requirements"
    write_fallback_requirements "$src"
  fi

  python3 - "$src" "$dst" <<'PYREQ'
from pathlib import Path
import re, sys
src, dst = map(Path, sys.argv[1:3])
text = src.read_text(encoding='utf-8', errors='replace')
text = text.replace('psycopg2-binary==2.9.9', 'psycopg2-binary>=2.9.12')
text = text.replace('psycopg2-binary==2.9.10', 'psycopg2-binary>=2.9.12')
text = text.replace('psycopg2-binary==2.9.11', 'psycopg2-binary>=2.9.12')
raw = []
for line in text.splitlines():
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    if ' ' in line and not line.startswith(('-e ', '--')):
        raw.extend(x for x in re.split(r'\s+', line) if x)
    else:
        raw.append(line)
seen, out = set(), []
for item in raw:
    key = re.split(r'[<>=!~]', item, 1)[0].lower()
    if key in seen:
        continue
    seen.add(key)
    out.append(item)
if not any(x.lower().startswith('psycopg2-binary') for x in out):
    out.append('psycopg2-binary>=2.9.12')
if not any(x.lower().startswith('bcrypt') for x in out):
    out.append('bcrypt==4.0.1')
dst.write_text('\n'.join(out) + '\n', encoding='utf-8')
PYREQ
}

repair_repo_compat() {
  local backend frontend req tmp
  backend="$(backend_dir)"
  frontend="$(frontend_dir)"
  req="${backend}/requirements.txt"
  tmp="${STATE_DIR}/requirements.normalized.txt"

  [[ -d "$backend" ]] || fail "Backend directory not found: $backend"
  mkdir -p "$STATE_DIR"
  normalise_requirements "$req" "$tmp"
  install -m 0644 "$tmp" "$req"
  success "Python requirements normalised"

  if [[ -f "${backend}/main.py" ]]; then
    python3 - "${backend}/main.py" "$COCO_APP_VERSION" <<'PYMAIN'
from pathlib import Path
import re, sys
p = Path(sys.argv[1]); version = sys.argv[2]
s = p.read_text(encoding='utf-8', errors='replace')
s = re.sub(r'version\s*=\s*["\']0\.[0-9.]+["\']', f'version="{version}"', s)
s = re.sub(r'"version"\s*:\s*"0\.[0-9.]+"', f'"version": "{version}"', s)
p.write_text(s, encoding='utf-8')
PYMAIN
  fi

  if [[ -f "${frontend}/package.json" ]]; then
    python3 - "${frontend}/package.json" "$COCO_APP_VERSION" <<'PYPKG' || warn "Could not update frontend package.json version"
from pathlib import Path
import json, sys
p = Path(sys.argv[1]); version = sys.argv[2]
data = json.loads(p.read_text(encoding='utf-8'))
data['version'] = version
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PYPKG
  fi
}


step_coco() {
  mkdir -p "$COCO_DIR" "$COCO_SSL_DIR" "${COCO_DIR}/logs"

  cat > "$COCO_ENV_FILE" <<EOF
# COCO Environment — generated $(date -Is)
EOF
  chmod 600 "$COCO_ENV_FILE"

  env_set SECRET_KEY          "$SECRET_KEY"
  env_set COCO_IP             "$COCO_IP"
  env_set COCO_PORT           "443"
  env_set COCO_APP_VERSION    "$COCO_APP_VERSION"
  env_set PVE_HOSTNAME        "$PVE_HOSTNAME"
  env_set PVE_NODE            "$PVE_HOSTNAME"
  env_set PROXMOX_HOST        "$COCO_IP"
  env_set PROXMOX_USER        "root@pam"
  env_set PROXMOX_PASSWORD    "$PVE_ROOT_PASSWORD"
  env_set PROXMOX_NODE        "$PVE_HOSTNAME"
  env_set COCO_REPO_DIR       "$COCO_REPO_DIR"
  env_set SSL_CERT            "${COCO_SSL_DIR}/coco.crt"
  env_set SSL_KEY             "${COCO_SSL_DIR}/coco.key"

  if [[ ! -d "$COCO_REPO_DIR/.git" ]]; then
    run_cmd "Cloning COCO repository" \
      git clone --branch "$COCO_REPO_BRANCH" "$COCO_REPO_URL" "$COCO_REPO_DIR"
  else
    run_cmd_allow_fail "Resetting local repository changes" git -C "$COCO_REPO_DIR" reset --hard
    run_cmd "Updating COCO repository" git -C "$COCO_REPO_DIR" pull --ff-only origin "$COCO_REPO_BRANCH"
  fi

  local backend frontend
  backend="$(backend_dir)"
  frontend="$(frontend_dir)"
  [[ -d "$backend" ]] || fail "Backend directory not found: $backend"
  [[ -d "$frontend" ]] || warn "Frontend directory not found: $frontend"

  env_set COCO_BACKEND_DIR  "$backend"
  env_set COCO_FRONTEND_DIR "$frontend"
  repair_repo_compat
  write_version_file
  success "COCO repository ready at $COCO_REPO_DIR"
}

step_backend() {
  local backend req req_install
  backend="$(backend_dir)"
  [[ -d "$backend" ]] || fail "Backend dir missing: $backend"

  run_cmd "Installing Python build dependencies" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev libpq-dev pkg-config

  if [[ ! -x "$COCO_VENV_DIR/bin/python3" ]]; then
    run_cmd "Creating Python venv" python3 -m venv "$COCO_VENV_DIR"
  else
    success "Python venv already exists"
  fi
  run_cmd "Upgrading pip" "$COCO_VENV_DIR/bin/pip" install --quiet --upgrade pip setuptools wheel

  req="${backend}/requirements.txt"
  req_install="${STATE_DIR}/requirements.install.txt"
  normalise_requirements "$req" "$req_install"

  run_cmd "Installing Python requirements" "$COCO_VENV_DIR/bin/pip" install --quiet --prefer-binary -r "$req_install"

  run_cmd "Verifying critical Python packages" "$COCO_VENV_DIR/bin/python3" - <<'PYVERIFY'
import importlib
for name in ('fastapi', 'uvicorn', 'sqlalchemy', 'psycopg2', 'redis', 'jose', 'passlib'):
    importlib.import_module(name)
print('critical imports ok')
PYVERIFY

  if find "$backend" -name '*.py' -print -quit | grep -q .; then
    run_cmd "Checking backend Python syntax" "$COCO_VENV_DIR/bin/python3" -m compileall -q "$backend"
  fi
}

step_postgres() {
  run_cmd "Installing PostgreSQL" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql postgresql-client
  run_cmd "Enabling PostgreSQL" systemctl enable --now postgresql

  local db_pass
  db_pass="$(env_get COCO_DB_PASSWORD || true)"
  [[ -z "$db_pass" ]] && db_pass="$(openssl rand -hex 24)"

  local sql old_umask
  sql="$(mktemp /tmp/coco-postgres.XXXXXX.sql)"
  old_umask="$(umask)"
  umask 077
  cat > "$sql" <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'coco') THEN
    CREATE ROLE coco LOGIN PASSWORD '${db_pass}';
  ELSE
    ALTER ROLE coco WITH LOGIN PASSWORD '${db_pass}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE coco OWNER coco'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'coco')\gexec
ALTER DATABASE coco OWNER TO coco;
GRANT ALL PRIVILEGES ON DATABASE coco TO coco;
EOF
  umask "$old_umask"
  chown postgres:postgres "$sql"
  chmod 600 "$sql"
  run_cmd "Configuring COCO database" runuser -u postgres -- psql -v ON_ERROR_STOP=1 -f "$sql"
  rm -f "$sql"

  env_set COCO_DB_PASSWORD "$db_pass"
  env_set DB_URL            "postgresql://coco:${db_pass}@localhost/coco"
  env_set DATABASE_URL      "postgresql://coco:${db_pass}@localhost/coco"
  env_set REDIS_URL         "redis://localhost:6379"
}

step_redis() {
  run_cmd "Installing Redis" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server
  run_cmd "Enabling Redis" systemctl enable --now redis-server
}

download_with_fallback() {
  local dest="$1" primary="$2" fallback="$3"
  set +e
  curl -fsSL "$primary" -o "$dest" >> "$LOG_FILE" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "Primary download failed — trying fallback"
    run_cmd "Downloading fallback" curl -fsSL "$fallback" -o "$dest"
  fi
}


apt_package_available() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
}

package_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qx 'install ok installed'
}

select_first_available_package() {
  local pkg
  for pkg in "$@"; do
    if apt_package_available "$pkg"; then
      printf '%s' "$pkg"
      return 0
    fi
  done
  return 1
}

add_available_package() {
  local __array_name="$1"; shift
  local pkg
  pkg="$(select_first_available_package "$@" || true)"
  if [[ -n "$pkg" ]]; then
    eval "$__array_name+=("$pkg")"
    return 0
  fi
  return 1
}

remove_installed_packages_if_present() {
  local label="$1"; shift
  local pkg remove_pkgs=()
  for pkg in "$@"; do
    if package_installed "$pkg"; then
      remove_pkgs+=("$pkg")
    fi
  done

  if [[ ${#remove_pkgs[@]} -eq 0 ]]; then
    success "$label: no installed matching packages"
    return 0
  fi

  run_cmd "$label" env DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${remove_pkgs[@]}"
}


ensure_guacd_service() {
  systemctl daemon-reload >/dev/null 2>&1 || true

  if systemctl list-unit-files 2>/dev/null | grep -q '^guacd\.service'; then
    run_cmd "Enabling guacd" systemctl enable --now guacd
    return 0
  fi

  if [[ -x /usr/local/sbin/guacd ]]; then
    cat > /etc/systemd/system/guacd.service <<'EOF'
[Unit]
Description=Apache Guacamole proxy daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/guacd -f
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    run_cmd "Reloading systemd for guacd" systemctl daemon-reload
    run_cmd "Enabling guacd" systemctl enable --now guacd
    return 0
  fi

  fail "guacd binary was not installed"
}

step_guacamole() {
  # Build dependencies. Debian 13/Trixie removed freerdp2-dev; freerdp3-dev is
  # the correct package there. The installer therefore resolves package names
  # before apt-get install instead of trying a known-bad package first.
  run_cmd "Updating package index before Guacamole dependencies" apt-get update -qq

  local deps=()
  local pkg missing=()
  local required_deps=(
    build-essential make gcc g++ pkg-config autoconf automake
    libcairo2-dev libpng-dev libtool-bin uuid-dev
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
    libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev
    libwebsockets-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev
    tomcat10 tomcat10-admin wget curl
  )
  local optional_deps=(
    libossp-uuid-dev
  )

  for pkg in "${required_deps[@]}"; do
    if apt_package_available "$pkg"; then
      deps+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "Required Guacamole build packages not available in apt: ${missing[*]}"
  fi

  for pkg in "${optional_deps[@]}"; do
    if apt_package_available "$pkg"; then
      deps+=("$pkg")
    else
      warn "Optional Guacamole package not available: $pkg"
    fi
  done

  add_available_package deps libjpeg62-turbo-dev libjpeg-dev \
    || fail "No JPEG development package available (tried libjpeg62-turbo-dev, libjpeg-dev)"

  if [[ "${COCO_GUAC_ENABLE_RDP}" == "1" ]]; then
    if add_available_package deps freerdp2-dev freerdp3-dev; then
      success "FreeRDP development package selected; RDP support requested"
    else
      warn "RDP support requested but no FreeRDP development package is available; building without RDP"
      COCO_GUAC_ENABLE_RDP="0"
    fi
  else
    warn "RDP support disabled by default to avoid Debian 13 / FreeRDP 3 build failures; SSH/VNC/Telnet remain enabled"
    remove_installed_packages_if_present "Removing installed FreeRDP development packages while RDP support is disabled"       freerdp2-dev freerdp3-dev libfreerdp-dev libfreerdp2-dev libfreerdp3-dev
  fi

  run_cmd "Installing Guacamole build dependencies" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${deps[@]}"

  # Build guacd from source
  local tar_file="/tmp/guacamole-server-${GUAC_VERSION}.tar.gz"
  local src_dir="/tmp/guacamole-server-${GUAC_VERSION}"
  download_with_fallback "$tar_file" \
    "https://downloads.apache.org/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz" \
    "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz"

  rm -rf "$src_dir"
  run_cmd "Extracting guacamole-server" tar -xzf "$tar_file" -C /tmp
  pushd "$src_dir" >/dev/null

  local configure_args=(--with-init-dir=/etc/init.d)
  if [[ "${COCO_GUAC_ENABLE_RDP}" != "1" ]]; then
    if ./configure --help 2>/dev/null | grep -q -- '--disable-rdp'; then
      configure_args+=(--disable-rdp)
    else
      warn "guacamole-server configure does not expose --disable-rdp; continuing without explicit RDP disable"
    fi
  else
    # FreeRDP 3.x exposes deprecated APIs that guacamole-server 1.6.0 may treat
    # as build errors. This macro hides those deprecated FreeRDP 3 declarations
    # where supported. FreeRDP 2 ignores it.
    export CPPFLAGS="${CPPFLAGS:-} -DWITHOUT_FREERDP_3x_DEPRECATED"
  fi

  run_cmd "Configuring guacd" ./configure "${configure_args[@]}"
  run_cmd "Building guacd (this takes a few minutes)" make -j"$(nproc)"
  run_cmd "Installing guacd" make install
  popd >/dev/null
  run_cmd "Updating shared library cache" ldconfig
  rm -rf "$tar_file" "$src_dir"

  # Deploy Guacamole WAR to Tomcat
  local war_file="/tmp/guacamole-${GUAC_VERSION}.war"
  download_with_fallback "$war_file" \
    "https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war" \
    "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war"
  mkdir -p /var/lib/tomcat10/webapps
  cp "$war_file" /var/lib/tomcat10/webapps/guacamole.war
  rm -f "$war_file"
  success "Guacamole WAR deployed"

  # Configure Guacamole
  mkdir -p /etc/guacamole/{extensions,lib}
  mkdir -p /usr/share/tomcat10/.guacamole

  cat > /etc/guacamole/guacamole.properties <<'EOF'
guacd-hostname: localhost
guacd-port: 4822
auth-provider: net.sourceforge.guacamole.net.basic.BasicFileAuthenticationProvider
basic-user-mapping: /etc/guacamole/user-mapping.xml
EOF
  ln -sfn /etc/guacamole /usr/share/tomcat10/.guacamole

  local guac_pass
  guac_pass="$(env_get GUACAMOLE_PASS || true)"
  [[ -z "$guac_pass" ]] && guac_pass="$(openssl rand -hex 24)"

  cat > /etc/guacamole/user-mapping.xml <<EOF
<user-mapping>
    <authorize username="coco" password="${guac_pass}">
    </authorize>
</user-mapping>
EOF
  chmod 640 /etc/guacamole/user-mapping.xml

  # Set ownership for Tomcat group
  local tgrp="tomcat"
  getent group "$tgrp" >/dev/null 2>&1 || tgrp="tomcat10"
  getent group "$tgrp" >/dev/null 2>&1 || tgrp="root"
  chown root:"$tgrp" /etc/guacamole/user-mapping.xml

  ensure_guacd_service
  run_cmd "Enabling Tomcat 10" systemctl enable --now tomcat10

  env_set GUACAMOLE_URL  "http://localhost:8080/guacamole"
  env_set GUACAMOLE_PASS "$guac_pass"
  success "Guacamole accessible at http://localhost:8080/guacamole"
}

first_line() {
  local s="${1:-}"
  printf '%s' "${s%%$'\n'*}"
}

step_ansible() {
  run_cmd "Installing Ansible" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible ansible-core
  if command -v ansible >/dev/null 2>&1; then
    local ansible_version
    ansible_version="$(ansible --version 2>/dev/null || true)"
    success "$(first_line "${ansible_version:-ansible installed}")"
  fi
}

step_packer() {
  local arch
  arch="$(dpkg --print-architecture)"
  [[ "$arch" == "amd64" || "$arch" == "arm64" ]] || fail "Unsupported arch for Packer: $arch"
  local zip="/tmp/packer.zip"
  run_cmd "Downloading Packer ${PACKER_VERSION}" wget -q \
    "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_${arch}.zip" \
    -O "$zip"
  run_cmd "Installing Packer" unzip -o -q "$zip" -d /usr/local/bin/
  rm -f "$zip"
  chmod +x /usr/local/bin/packer
  local packer_version
  packer_version="$(packer --version 2>/dev/null || true)"
  success "Packer: $(first_line "${packer_version:-installed}")"
}

step_node() {
  run_cmd "Adding Node.js ${NODE_MAJOR}.x repository" \
    bash -c "curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -"
  run_cmd "Installing Node.js" env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  success "Node.js: $(node --version)  npm: $(npm --version)"
}

step_ssl() {
  mkdir -p "$COCO_SSL_DIR"
  if [[ -f "${COCO_SSL_DIR}/coco.crt" && -f "${COCO_SSL_DIR}/coco.key" ]]; then
    success "SSL certificate already exists"
    return 0
  fi
  run_cmd "Generating self-signed SSL certificate (365 days)" openssl req -x509 -nodes \
    -days 365 -newkey rsa:2048 \
    -keyout "${COCO_SSL_DIR}/coco.key" \
    -out    "${COCO_SSL_DIR}/coco.crt" \
    -subj   "/C=CH/ST=COCO/L=COCO/O=COCO/CN=${COCO_IP}"
  chmod 600 "${COCO_SSL_DIR}/coco.key"
}

repair_frontend_compat() {
  local frontend src_dir api_file pkg_file
  frontend="$(frontend_dir)"
  src_dir="${frontend}/src"
  api_file="${src_dir}/lib/api.js"
  pkg_file="${frontend}/package.json"

  [[ -d "$frontend" ]] || return 0
  mkdir -p "${src_dir}/lib"

  # Some repo snapshots reference ../lib/api from pages but do not contain the file.
  # Create a conservative API client that matches the backend routes used by the UI.
  if [[ ! -f "$api_file" ]]; then
    cat > "$api_file" <<'APIEOF'
import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  headers: { 'Content-Type': 'application/json' },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('coco_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('coco_token')
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export const authApi = {
  login: (email, password) => api.post('/auth/login', { email, password }),
  register: (data) => api.post('/auth/register', data),
  me: () => api.get('/auth/me'),
  generateInvite: (team_type) => api.post(`/auth/invite/generate?team_type=${team_type}`),
}

export const gamesApi = {
  list: () => api.get('/games/'),
  get: (id) => api.get(`/games/${id}`),
  create: (data) => api.post('/games/', data),
  start: (id) => api.post(`/games/${id}/start`),
  join: (id, code) => api.post(`/games/${id}/join?join_code=${code}`),
  submitFlag: (id, flag) => api.post(`/games/${id}/flag`, { flag }),
  surrender: (id) => api.post(`/games/${id}/surrender`),
}

export const adminApi = {
  users: () => api.get('/admin/users'),
  stats: () => api.get('/admin/stats'),
  toggleUser: (id) => api.patch(`/admin/users/${id}/toggle`),
  audit: () => api.get('/admin/audit'),
}

export default api
APIEOF
    success "Created missing frontend API helper: $api_file"
  fi

  # Support older snapshots that import ../../lib/api from src/pages/*.
  mkdir -p "${frontend}/lib"
  cp -f "$api_file" "${frontend}/lib/api.js"

  # Some snapshots import ../../store/auth from src/pages/*, which resolves to
  # <frontend>/store/auth.js. Others import ../store/auth, which resolves to
  # <frontend>/src/store/auth.js. Create both shims so Vite can resolve either.
  for auth_file in "${frontend}/store/auth.js" "${src_dir}/store/auth.js"; do
    if [[ ! -f "$auth_file" ]]; then
      mkdir -p "$(dirname "$auth_file")"
      cat > "$auth_file" <<'AUTHEOF'
import { create } from 'zustand'
import api, { authApi } from '../lib/api.js'

const tokenKey = 'coco_token'

export const useAuthStore = create((set, get) => ({
  token: localStorage.getItem(tokenKey),
  user: null,
  isAuthenticated: !!localStorage.getItem(tokenKey),
  loading: false,
  error: null,

  login: async (email, password) => {
    set({ loading: true, error: null })
    try {
      const res = await authApi.login(email, password)
      const data = res.data || {}
      const token = data.access_token || data.token || data.accessToken
      if (token) {
        localStorage.setItem(tokenKey, token)
        api.defaults.headers.common.Authorization = `Bearer ${token}`
      }
      set({ token, user: data.user || null, isAuthenticated: !!token, loading: false })
      return data
    } catch (err) {
      const message = err.response?.data?.detail || err.message || 'Login failed'
      set({ error: message, loading: false })
      throw err
    }
  },

  logout: () => {
    localStorage.removeItem(tokenKey)
    delete api.defaults.headers.common.Authorization
    set({ token: null, user: null, isAuthenticated: false })
  },

  fetchMe: async () => {
    try {
      const res = await authApi.me()
      set({ user: res.data || null, isAuthenticated: true })
      return res.data
    } catch (err) {
      get().logout()
      return null
    }
  },

  setUser: (user) => set({ user }),
}))

export default useAuthStore
AUTHEOF
      success "Created missing frontend auth store shim: $auth_file"
    fi
  done

  if [[ -f "$pkg_file" ]]; then
    python3 - "$pkg_file" "$COCO_APP_VERSION" <<'PYPKG' || warn "Could not normalize frontend package.json"
from pathlib import Path
import json, sys
p = Path(sys.argv[1]); version = sys.argv[2]
data = json.loads(p.read_text(encoding='utf-8'))
data['version'] = version
data.setdefault('scripts', {})
data['scripts'].setdefault('build', 'vite build')
data.setdefault('dependencies', {})
for name, spec in {
    '@vitejs/plugin-react': '^4.3.1',
    'vite': '^5.4.0',
    'react': '^18.2.0',
    'react-dom': '^18.2.0',
    'react-router-dom': '^6.26.0',
    'axios': '^1.7.7',
    'zustand': '^4.5.5',
    'lucide-react': '^0.468.0',
}.items():
    if name.startswith('@vitejs/'):
        data.setdefault('devDependencies', {})
        data['devDependencies'].setdefault(name, spec)
    else:
        data['dependencies'].setdefault(name, spec)
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PYPKG
  fi
}

write_fallback_frontend_dist() {
  local frontend dist
  frontend="$(frontend_dir)"
  dist="${frontend}/dist"
  mkdir -p "$dist"
  cat > "${dist}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>COCO</title>
  <style>
    body { margin: 0; font-family: system-ui, -apple-system, Segoe UI, sans-serif; background: #09090b; color: #fafafa; }
    main { max-width: 820px; margin: 8vh auto; padding: 32px; border: 1px solid #27272a; border-radius: 16px; background: #111113; }
    code { background: #18181b; padding: 2px 6px; border-radius: 6px; }
    a { color: #67e8f9; }
  </style>
</head>
<body>
  <main>
    <h1>COCO Backend installed</h1>
    <p>The React frontend source did not build successfully during installation, so this fallback page was generated to keep the service deployable.</p>
    <p>Backend health endpoint: <a href="/api/health">/api/health</a></p>
    <p>Check frontend build logs with: <code>tail -n 120 ${LOG_FILE}</code></p>
  </main>
</body>
</html>
EOF
  success "Fallback frontend dist generated at $dist"
}

step_frontend() {
  local frontend build_rc
  frontend="$(frontend_dir)"
  if [[ ! -d "$frontend" ]]; then
    warn "Frontend source not found at $frontend — generating fallback dist"
    mkdir -p "$frontend"
    write_fallback_frontend_dist
    return 0
  fi

  repair_frontend_compat

  pushd "$frontend" >/dev/null
  if [[ -f package-lock.json ]]; then
    run_cmd "Installing frontend dependencies (npm install)" npm install --silent
  else
    run_cmd "Installing frontend dependencies (npm install)" npm install --silent
  fi

  info "Building React/Vite frontend"
  if npm run build >> "$LOG_FILE" 2>&1; then
    build_rc=0
  else
    build_rc=$?
  fi
  if [[ $build_rc -ne 0 ]]; then
    warn "React frontend build failed; applying compatibility repair and retrying once"
    popd >/dev/null
    repair_frontend_compat
    pushd "$frontend" >/dev/null
    if npm run build >> "$LOG_FILE" 2>&1; then
      build_rc=0
    else
      build_rc=$?
    fi
  fi
  popd >/dev/null

  if [[ $build_rc -ne 0 ]]; then
    warn "React frontend build still failed; generating fallback dist so installation can continue"
    write_fallback_frontend_dist
  else
    success "Frontend built at ${frontend}/dist"
  fi
}
step_dbinit() {
  local backend
  backend="$(backend_dir)"
  [[ -d "$backend" ]] || fail "Backend dir missing: $backend"
  load_env_file

  info "Initialising database schema"
  PYTHONPATH="$backend" "$COCO_VENV_DIR/bin/python3" <<'PY'
import importlib, os, sys
backend = os.environ.get('PYTHONPATH', '/opt/coco/repo/web/backend')
sys.path.insert(0, backend)
from core.database import Base, engine
for mod in ('models.user', 'models.game'):
    try:    importlib.import_module(mod)
    except Exception as e: print(f'WARN: {mod}: {e}')
Base.metadata.create_all(bind=engine)
print('Schema initialised.')
PY
}

step_admin() {
  local backend
  backend="$(backend_dir)"
  [[ -d "$backend" ]] || fail "Backend dir missing: $backend"
  load_env_file

  info "Creating/updating admin user: ${COCO_ADMIN_EMAIL}"
  COCO_ADMIN_EMAIL="$COCO_ADMIN_EMAIL" \
  COCO_ADMIN_PASSWORD="$COCO_ADMIN_PASSWORD" \
  PYTHONPATH="$backend" \
  "$COCO_VENV_DIR/bin/python3" <<'PY'
import os, sys
backend = os.environ.get('PYTHONPATH', '/opt/coco/repo/web/backend')
sys.path.insert(0, backend)
from core.database import SessionLocal
from core.security import hash_password
from models.user import User, UserRole
email    = os.environ['COCO_ADMIN_EMAIL']
password = os.environ['COCO_ADMIN_PASSWORD']
db = SessionLocal()
try:
    u = db.query(User).filter(User.email == email).first()
    if u:
        u.hashed_password = hash_password(password)
        u.role = UserRole.admin
        u.is_active = True
        db.commit()
        print('Admin updated.')
    else:
        db.add(User(email=email, username='admin',
                    hashed_password=hash_password(password),
                    role=UserRole.admin, is_active=True))
        db.commit()
        print('Admin created.')
finally:
    db.close()
PY
  success "Admin user ready: ${COCO_ADMIN_EMAIL}"
}

step_service() {
  local backend
  backend="$(backend_dir)"

  cat > /etc/systemd/system/coco.service <<EOF
[Unit]
Description=COCO Attack & Defense Platform
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=${backend}
EnvironmentFile=${COCO_ENV_FILE}
Environment=PYTHONPATH=${backend}
Environment=COCO_APP_VERSION=${COCO_APP_VERSION}
ExecStart=${COCO_VENV_DIR}/bin/uvicorn main:app \\
  --host 0.0.0.0 \\
  --port 443 \\
  --ssl-certfile ${COCO_SSL_DIR}/coco.crt \\
  --ssl-keyfile ${COCO_SSL_DIR}/coco.key \\
  --workers 4 \\
  --access-log \\
  --log-level info
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  run_cmd "Reloading systemd" systemctl daemon-reload
  run_cmd "Enabling COCO service" systemctl enable coco.service
  run_cmd_allow_fail "Starting COCO service" systemctl restart coco.service

  sleep 3
  if systemctl is-active --quiet coco.service; then
    success "COCO service running on port 443"
  else
    warn "COCO service not active — check: journalctl -xeu coco.service"
  fi
}

remove_resume_service() {
  if [[ -f "$COCO_RESUME_SERVICE" ]]; then
    run_cmd_allow_fail "Disabling resume service" systemctl disable coco-install-resume.service
    rm -f "$COCO_RESUME_SERVICE"
    run_cmd_allow_fail "Reloading systemd" systemctl daemon-reload
  fi
}

print_done() {
  remove_resume_service
  rm -f "$COCO_CONFIG_FILE" "$CURRENT_STEP_FILE"
  write_version_file
  echo "complete" > "$STATE_FILE"

  echo ""
  printf '%b' "$GREEN"
  cat <<'DONE'
  ────────────────────────────────────────────────
   COCO installation complete.
  ────────────────────────────────────────────────
DONE
  printf '%b' "$RESET"
  echo ""
  printf '  COCO Web-GUI :  https://%s\n'      "$COCO_IP"
  printf '  Proxmox GUI  :  https://%s:8006\n' "$COCO_IP"
  echo ""
  echo "  Admin login"
  printf '  Email        :  %s\n' "$COCO_ADMIN_EMAIL"
  echo "  Password     :  (set during install)"
  echo ""
  echo "  Useful commands:"
  echo "  systemctl status coco"
  echo "  journalctl -xeu coco"
  printf '  %s\n' "$LOG_FILE"
  echo ""
  divider
}


heal_state_markers() {
  if is_done bootstrap && ! command -v curl >/dev/null 2>&1; then
    warn "Removing stale bootstrap marker — tools missing"
    rm -f "${STEP_DIR}/bootstrap.done"
  fi
  if is_done proxmox && ! command -v pveversion >/dev/null 2>&1; then
    warn "Removing stale proxmox marker — pveversion missing"
    rm -f "${STEP_DIR}/proxmox.done"
  fi
  if is_done kernel_reboot && [[ "$(uname -r)" != *pve* ]]; then
    warn "Removing stale kernel_reboot marker — Proxmox kernel not active"
    rm -f "${STEP_DIR}/kernel_reboot.done"
  fi
  if is_done coco && [[ ! -d "$COCO_REPO_DIR/.git" ]]; then
    warn "Removing stale coco marker — repository missing"
    rm -f "${STEP_DIR}/coco.done"
  fi
  if is_done backend; then
    if [[ ! -x "$COCO_VENV_DIR/bin/python3" ]] || ! "$COCO_VENV_DIR/bin/python3" - <<'PYCHECK' >/dev/null 2>&1
import importlib
for name in ('fastapi','uvicorn','sqlalchemy','psycopg2'):
    importlib.import_module(name)
PYCHECK
    then
      warn "Removing stale backend marker — venv/packages incomplete"
      rm -f "${STEP_DIR}/backend.done"
    fi
  fi
  if is_done postgres; then
    if ! systemctl is-active --quiet postgresql || ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='coco'" 2>/dev/null | grep -qx 1; then
      warn "Removing stale postgres marker — database missing or service inactive"
      rm -f "${STEP_DIR}/postgres.done"
    fi
  fi
  if is_done redis && ! systemctl is-active --quiet redis-server; then
    warn "Removing stale redis marker — service inactive"
    rm -f "${STEP_DIR}/redis.done"
  fi
  if is_done ssl && { [[ ! -f "${COCO_SSL_DIR}/coco.crt" ]] || [[ ! -f "${COCO_SSL_DIR}/coco.key" ]]; }; then
    warn "Removing stale ssl marker — certificate missing"
    rm -f "${STEP_DIR}/ssl.done"
  fi
}


# ── Main ───────────────────────────────────────────────────
run_all() {
  with_step bootstrap      "Installing bootstrap dependencies"          step_bootstrap
  with_step proxmox        "Installing Proxmox VE 9"                   step_proxmox
  with_step kernel_reboot  "Activating Proxmox kernel"                 step_kernel_reboot
  with_step sysconfig      "Configuring system"                        step_sysconfig
  with_step coco           "Setting up COCO repository"                step_coco
  with_step backend        "Installing FastAPI backend"                step_backend
  with_step postgres       "Installing PostgreSQL"                     step_postgres
  with_step redis          "Installing Redis"                          step_redis
  with_step guacamole      "Installing Apache Guacamole"              step_guacamole
  with_step ansible        "Installing Ansible"                        step_ansible
  with_step packer         "Installing Packer"                         step_packer
  with_step node           "Installing Node.js ${NODE_MAJOR}"          step_node
  with_step ssl            "Generating SSL certificate"                step_ssl
  with_step frontend       "Building React frontend"                   step_frontend
  with_step dbinit         "Initialising database schema"              step_dbinit
  with_step admin          "Creating admin user"                       step_admin
  with_step service        "Deploying COCO service"                    step_service
  print_done
}

main() {
  parse_args "$@"
  ensure_runtime_dirs
  repair_apt_keyring_permissions
  print_logo
  require_root

  if [[ "$RESUME" == "1" ]]; then
    info "Resuming after reboot"
    load_install_config
    heal_state_markers
    run_all
    return 0
  fi

  check_os
  collect_config
  heal_state_markers
  run_all
}

main "$@"
