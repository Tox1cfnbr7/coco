#!/usr/bin/env bash
# ============================================================
#   COCO — Template Builder v2
#   All ISOs downloaded automatically — no manual uploads.
#
#   Usage:
#     bash build-templates.sh              # menu
#     bash build-templates.sh --all        # all templates
#     bash build-templates.sh --template kali
#     bash build-templates.sh --template debian12
#     bash build-templates.sh --template win2022
#     bash build-templates.sh --template win10
#     bash build-templates.sh --template dc02-ca
#     bash build-templates.sh --template siem
#
#   Template VMIDs are FIXED in each .pkr.hcl and already match
#   web/backend/services/vm_config.py — no manual edit needed after a build.
#
#   Windows ISOs: set WIN_ISO_FILE=local:iso/<file>.iso to use a staged ISO.
# ============================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/coco"
LOG_FILE="${LOG_DIR}/packer-build.log"

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

mkdir -p "$LOG_DIR" && touch "$LOG_FILE"

# ── Template map: key → directory name ─────────────────────
# MUST match the folder names in templates/
declare -A TEMPLATE_DIRS=(
  [kali]="kali"
  [debian12]="debian12"
  [win2022]="windows-server-2022"
  [win10]="windows-10"
  [dc02-ca]="dc02-ca"
  [siem]="siem"
)

declare -A TEMPLATE_LABELS=(
  [kali]="Kali Linux 2024"
  [debian12]="Debian 12 (Web/Linux base)"
  [win2022]="Windows Server 2022 (DC/MSSQL)"
  [win10]="Windows 10 Workstation"
  [dc02-ca]="Windows Server 2022 (DC-02 + AD CS)"
  [siem]="SIEM Stack (Elastic + Wazuh + Kibana)"
)

# ── Load COCO config ────────────────────────────────────────
[[ -f /opt/coco/.env ]] && { set -a; source /opt/coco/.env; set +a; }

PROXMOX_URL="${PROXMOX_URL:-https://127.0.0.1:8006/api2/json}"
PROXMOX_USER="${PROXMOX_USER:-root@pam}"
PROXMOX_NODE="${PROXMOX_NODE:-$(hostname)}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-${PVE_ROOT_PASSWORD:-}}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-local-lvm}"
ISO_STORAGE="${ISO_STORAGE:-local}"

# ── Args ────────────────────────────────────────────────────
BUILD_ALL=0; TEMPLATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)        BUILD_ALL=1 ;;
    --template)   TEMPLATE="$2"; shift ;;
    -h|--help)
      echo "Usage: $0 [--all] [--template kali|debian12|win2022|win10|dc02-ca|siem]"
      exit 0 ;;
  esac
  shift
done

# ── Checks ──────────────────────────────────────────────────
command -v packer >/dev/null 2>&1 || fail "Packer not found — run install.sh first"
[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run as root"

if [[ -z "$PROXMOX_PASSWORD" ]]; then
  read -rsp "  Proxmox password: " PROXMOX_PASSWORD; echo ""
fi

# Test Proxmox connection
rc=$(curl -sk -o /dev/null -w "%{http_code}" \
  --data "username=${PROXMOX_USER}&password=${PROXMOX_PASSWORD}" \
  "${PROXMOX_URL}/access/ticket")
[[ "$rc" == "200" ]] || fail "Cannot reach Proxmox ($rc) — check credentials"
success "Proxmox connection OK"

# ── Build function ──────────────────────────────────────────
build_template() {
  local key="$1"
  local dir_name="${TEMPLATE_DIRS[$key]:-}"
  local label="${TEMPLATE_LABELS[$key]:-$key}"

  [[ -n "$dir_name" ]] || fail "Unknown template key: '$key'. Valid: ${!TEMPLATE_DIRS[*]}"

  local tpl_dir="${SCRIPT_DIR}/${dir_name}"
  [[ -d "$tpl_dir" ]] || fail "Template directory not found: $tpl_dir"

  local log="/var/log/coco/packer-${key}.log"
  local pid_file="/var/run/coco-packer-${key}.pid"

  echo "" | tee -a "$LOG_FILE"
  printf '%b  >> Building: %s%b\n' "${BOLD}${CYAN}" "$label" "$RESET" | tee -a "$LOG_FILE"
  info "Directory: $tpl_dir"
  info "Log file:  $log"
  info "Watch progress: tail -f $log"

  cd "$tpl_dir"
  packer init . >> "$log" 2>&1

  # Write PID file before build starts
  echo $$ > "$pid_file"

  # Optional ISO overrides (env). For Windows, staging an ISO in Proxmox and
  # setting WIN_ISO_FILE=local:iso/<file>.iso is the reliable method.
  local extra_vars=()
  [[ -n "${WIN_ISO_FILE:-}"     ]] && extra_vars+=(-var "win_iso_file=${WIN_ISO_FILE}")
  [[ -n "${WIN_ISO_URL:-}"      ]] && extra_vars+=(-var "win_iso_url=${WIN_ISO_URL}")
  [[ -n "${WIN_ISO_CHECKSUM:-}" ]] && extra_vars+=(-var "win_iso_checksum=${WIN_ISO_CHECKSUM}")
  [[ -n "${ISO_URL:-}"          ]] && extra_vars+=(-var "iso_url=${ISO_URL}")
  [[ -n "${ISO_CHECKSUM:-}"     ]] && extra_vars+=(-var "iso_checksum=${ISO_CHECKSUM}")

  case "$key" in
    win2022|win10|dc02-ca)
      if [[ -z "${WIN_ISO_FILE:-}" ]]; then
        warn "Windows template '$key': no WIN_ISO_FILE set — Packer will try the"
        warn "Microsoft eval URL, which may rotate/expire. If the download fails,"
        warn "upload the eval ISO to Proxmox (Datacenter > Storage > ISO Images)"
        warn "and re-run:  WIN_ISO_FILE=local:iso/<file>.iso bash build-templates.sh --template $key"
      fi ;;
  esac

  PACKER_LOG=1 packer build \
    -var "proxmox_url=${PROXMOX_URL}" \
    -var "proxmox_user=${PROXMOX_USER}" \
    -var "proxmox_password=${PROXMOX_PASSWORD}" \
    -var "proxmox_node=${PROXMOX_NODE}" \
    -var "proxmox_storage=${PROXMOX_STORAGE}" \
    -var "iso_storage=${ISO_STORAGE}" \
    "${extra_vars[@]}" \
    -on-error=cleanup \
    . 2>&1 | tee -a "$log" | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  rm -f "$pid_file"
  cd "$SCRIPT_DIR"

  if [[ $rc -eq 0 ]]; then
    success "Template '${label}' built!"
    # Find the VMID
    local vmid
    vmid=$(grep -oP 'vmid: \K[0-9]+' "$log" 2>/dev/null | tail -1 || \
           grep -oP '"vmid":\K[0-9]+' "$log" 2>/dev/null | tail -1 || echo "?")
    [[ "$vmid" != "?" ]] && success "VMID: $vmid (fixed in the template; already matches vm_config.py)"
  else
    warn "Build failed for '${label}' (exit $rc). Check: $log"
    return $rc
  fi
}

print_vmids() {
  echo ""
  info "Current templates on Proxmox:"
  qm list 2>/dev/null | grep -E "coco-tpl|VMID" || true
  echo ""
  info "Template VMIDs are fixed (kali=9000 win2022=9001 dc02-ca=9002 debian12=9003 win10=9005 siem=9006)"
  info "and already match web/backend/services/vm_config.py — no manual edit needed."
}

# ── Menu ────────────────────────────────────────────────────
show_menu() {
  printf '%b' "$CYAN"
  cat << 'LOGO'
  ██████╗  ██████╗  ██████╗  ██████╗
 ██╔════╝ ██╔═══██╗██╔════╝ ██╔═══██╗
 ██║      ██║   ██║██║      ██║   ██║
 ╚██████╗ ╚██████╔╝╚██████╗ ╚██████╔╝
  ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝
         Template Builder v2
LOGO
  printf '%b  Node: %s  |  Storage: %s%b\n\n' "$RESET$CYAN" "$PROXMOX_NODE" "$PROXMOX_STORAGE" "$RESET"
  echo "  Templates:"
  echo "    1) kali     — Kali Linux 2024 (Red Team)"
  echo "    2) debian12  — Debian 12 (Web / Linux Services)"
  echo "    3) win2022   — Windows Server 2022 (DC + MSSQL)"
  echo "    4) win10     — Windows 10 Workstation"
  echo "    5) dc02-ca   — Windows Server 2022 (DC-02 + AD CS)"
  echo "    6) siem      — SIEM Stack (Elastic + Wazuh + Kibana)"
  echo "    a) All (recommended order)"
  echo ""
  read -rp "  Choice [a]: " choice
  choice="${choice:-a}"
}

# ── Main ────────────────────────────────────────────────────
if [[ "$BUILD_ALL" == "1" ]]; then
  for key in kali debian12 win2022 win10 dc02-ca siem; do
    build_template "$key" || warn "Continuing after: $key"
  done
  print_vmids
  exit 0
fi

if [[ -n "$TEMPLATE" ]]; then
  build_template "$TEMPLATE"
  print_vmids
  exit 0
fi

show_menu
case "${choice,,}" in
  1|kali)    build_template kali ;;
  2|debian12) build_template debian12 ;;
  3|win2022)  build_template win2022 ;;
  4|win10)    build_template win10 ;;
  5|dc02-ca)  build_template dc02-ca ;;
  6|siem)     build_template siem ;;
  a|*)
    for key in kali debian12 win2022 win10 dc02-ca siem; do
      build_template "$key" || warn "Continuing..."
    done
    ;;
esac

print_vmids
