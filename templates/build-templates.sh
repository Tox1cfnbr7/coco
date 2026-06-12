#!/usr/bin/env bash
# ============================================================
#   COCO — Template Builder
#   Builds all Proxmox VM templates via Packer.
#   ISOs are downloaded automatically — no manual uploads needed.
#
#   Usage:
#     bash build-templates.sh              # interactive menu
#     bash build-templates.sh --all        # build everything
#     bash build-templates.sh --template kali
#     bash build-templates.sh --template debian12
#     bash build-templates.sh --template win2022
#     bash build-templates.sh --template win10
#
#   After first build, note the VMIDs Proxmox assigned and update
#   TEMPLATES in web/backend/services/session_manager.py
# ============================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/coco"
LOG_FILE="${LOG_DIR}/packer-build.log"

# ── Colors ──────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi
info()    { printf '%b  [*]%b %s\n' "$CYAN"   "$RESET" "$*" | tee -a "$LOG_FILE"; }
success() { printf '%b  [+]%b %s\n' "$GREEN"  "$RESET" "$*" | tee -a "$LOG_FILE"; }
warn()    { printf '%b  [!]%b %s\n' "$YELLOW" "$RESET" "$*" | tee -a "$LOG_FILE"; }
fail()    { printf '%b  [-] %s%b\n' "$RED"    "$*" "$RESET" | tee -a "$LOG_FILE"; exit 1; }
section() { echo ""; printf '%b  >> %s%b\n' "${BOLD}${CYAN}" "$*" "$RESET"; echo ""; }

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# ── Load COCO config ────────────────────────────────────────
if [[ -f /opt/coco/.env ]]; then
  set -a; source /opt/coco/.env; set +a
fi

PROXMOX_URL="${PROXMOX_URL:-https://127.0.0.1:8006/api2/json}"
PROXMOX_USER="${PROXMOX_USER:-root@pam}"
PROXMOX_NODE="${PROXMOX_NODE:-$(hostname)}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-${PVE_ROOT_PASSWORD:-}}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-local-lvm}"
ISO_STORAGE="${ISO_STORAGE:-local}"

# ── Argument parsing ────────────────────────────────────────
BUILD_ALL=0
TEMPLATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)        BUILD_ALL=1 ;;
    --template)   TEMPLATE="$2"; shift ;;
    -h|--help)
      echo "Usage: $0 [--all] [--template kali|debian12|win2022|win10]"
      exit 0 ;;
  esac
  shift
done

# ── Check prerequisites ─────────────────────────────────────
check_prereqs() {
  command -v packer  >/dev/null 2>&1 || fail "Packer not found. Run install.sh first."
  command -v curl    >/dev/null 2>&1 || fail "curl not found"
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run as root"
}

# ── Collect Proxmox credentials if not set ──────────────────
collect_credentials() {
  if [[ -z "$PROXMOX_PASSWORD" ]]; then
    read -rsp "  Proxmox root password: " PROXMOX_PASSWORD; echo ""
  fi

  # Test connection
  local rc
  rc=$(curl -sk -o /dev/null -w "%{http_code}" \
    --data "username=${PROXMOX_USER}&password=${PROXMOX_PASSWORD}" \
    "${PROXMOX_URL}/access/ticket" 2>/dev/null)
  [[ "$rc" == "200" ]] || fail "Cannot connect to Proxmox at ${PROXMOX_URL} (HTTP $rc)"
  success "Proxmox connection verified"
}

# ── Packer build function ───────────────────────────────────
build_template() {
  local name="$1"
  local dir="${SCRIPT_DIR}/${name}"

  [[ -d "$dir" ]] || fail "Template directory not found: $dir"

  section "Building template: ${name}"
  info "Initialising Packer plugins..."
  cd "$dir"
  packer init . >> "$LOG_FILE" 2>&1

  info "Building ${name} (this may take 30-90 minutes)..."
  info "Live log: tail -f ${LOG_FILE}"

  PACKER_LOG=1 packer build \
    -var "proxmox_url=${PROXMOX_URL}" \
    -var "proxmox_user=${PROXMOX_USER}" \
    -var "proxmox_password=${PROXMOX_PASSWORD}" \
    -var "proxmox_node=${PROXMOX_NODE}" \
    -var "proxmox_storage=${PROXMOX_STORAGE}" \
    -var "iso_storage=${ISO_STORAGE}" \
    -on-error=cleanup \
    . 2>&1 | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  cd "$SCRIPT_DIR"

  if [[ $rc -eq 0 ]]; then
    success "Template '${name}' built successfully!"
    # Print the VMID from the log
    local vmid
    vmid=$(grep -o 'VM ID: [0-9]*\|vmid=[0-9]*\|new vm.*id [0-9]*' "$LOG_FILE" \
           | tail -1 | grep -o '[0-9]*$' || true)
    [[ -n "$vmid" ]] && success "VMID: ${vmid} — update session_manager.py TEMPLATES dict"
  else
    warn "Template '${name}' build failed (exit $rc). Check: $LOG_FILE"
    return $rc
  fi
}

# ── Interactive menu ─────────────────────────────────────────
show_menu() {
  printf '%b' "$CYAN"
  cat << 'LOGO'
  ██████╗  ██████╗  ██████╗  ██████╗
 ██╔════╝ ██╔═══██╗██╔════╝ ██╔═══██╗
 ██║      ██║   ██║██║      ██║   ██║
 ╚██████╗ ╚██████╔╝╚██████╗ ╚██████╔╝
  ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝
         Template Builder
LOGO
  printf '%b' "$RESET"
  echo ""
  printf '  Proxmox : %s\n' "$PROXMOX_URL"
  printf '  Node    : %s\n' "$PROXMOX_NODE"
  printf '  Storage : %s\n' "$PROXMOX_STORAGE"
  echo ""
  echo "  Templates:"
  echo "    1) kali          — Kali Linux 2024 (Red Team attacker)"
  echo "    2) debian12      — Debian 12 (Web/Linux service VMs)"
  echo "    3) win2022       — Windows Server 2022 (DC + MSSQL)"
  echo "    4) win10         — Windows 10 (Workstation)"
  echo "    a) All templates"
  echo ""
  read -rp "  Choice [a]: " choice
  choice="${choice:-a}"
}

# ── Main ─────────────────────────────────────────────────────
main() {
  check_prereqs
  collect_credentials

  if [[ "$BUILD_ALL" == "1" ]]; then
    for t in kali debian12 win2022 win10; do
      build_template "$t" || warn "Continuing after failed template: $t"
    done
    print_summary
    return
  fi

  if [[ -n "$TEMPLATE" ]]; then
    build_template "$TEMPLATE"
    return
  fi

  show_menu
  case "${choice,,}" in
    1|kali)    build_template kali ;;
    2|debian12) build_template debian12 ;;
    3|win2022)  build_template win2022 ;;
    4|win10)    build_template win10 ;;
    a|*)
      for t in kali debian12 win2022 win10; do
        build_template "$t" || warn "Continuing after: $t"
      done
      print_summary
      ;;
  esac
}

print_summary() {
  echo ""
  printf '%b  ────────────────────────────────────────────────%b\n' "$GREEN" "$RESET"
  printf '%b  All templates built!%b\n' "$GREEN" "$RESET"
  printf '%b  ────────────────────────────────────────────────%b\n' "$GREEN" "$RESET"
  echo ""
  echo "  Next step: update TEMPLATES dict in"
  echo "  /opt/coco/repo/web/backend/services/session_manager.py"
  echo "  with the VMID numbers shown above."
  echo ""
  echo "  Find VMIDs in Proxmox GUI or:"
  echo "  qm list | grep coco-tpl"
  echo ""
}

main "$@"
