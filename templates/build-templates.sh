#!/usr/bin/env bash
# ============================================================
#   COCO — Build Packer Templates
#   Run this ONCE on the Proxmox host to build all VM templates.
#   Prerequisites:
#     - Packer installed (done by install.sh)
#     - ISO files uploaded to Proxmox storage
#     - Windows Server 2022 Evaluation ISO at local:iso/windows-server-2022-eval.iso
#     - VirtIO ISO at local:iso/virtio-win.iso
#     - Kali ISO will be auto-downloaded
# ============================================================
set -e

PROXMOX_URL="${PROXMOX_URL:-https://127.0.0.1:8006/api2/json}"
PROXMOX_USER="${PROXMOX_USER:-root@pam}"
PROXMOX_NODE="${PROXMOX_NODE:-coco}"

echo "=== COCO Template Builder ==="
echo ""

source /opt/coco/.env 2>/dev/null || true
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-$PVE_ROOT_PASSWORD}"

if [[ -z "$PROXMOX_PASSWORD" ]]; then
  read -rsp "Proxmox password: " PROXMOX_PASSWORD; echo ""
fi

PACKER_VARS=(
  -var "proxmox_url=${PROXMOX_URL}"
  -var "proxmox_user=${PROXMOX_USER}"
  -var "proxmox_password=${PROXMOX_PASSWORD}"
  -var "proxmox_node=${PROXMOX_NODE}"
)

TEMPLATES_DIR="$(cd "$(dirname "$0")" && pwd)"

build_template() {
  local name="$1"
  local dir="${TEMPLATES_DIR}/${name}"
  echo ""
  echo ">>> Building: ${name}"
  cd "$dir"
  packer init .
  packer build "${PACKER_VARS[@]}" .
  echo ">>> Done: ${name}"
}

echo "Which templates to build?"
echo "  1) kali"
echo "  2) windows-dc"
echo "  3) windows-mssql"
echo "  4) webserver"
echo "  5) linux-vuln"
echo "  a) All"
read -rp "Choice [a]: " choice
choice="${choice:-a}"

case "$choice" in
  1) build_template kali ;;
  2) build_template windows-dc ;;
  3) build_template windows-mssql ;;
  4) build_template webserver ;;
  5) build_template linux-vuln ;;
  a|A|*)
    build_template kali
    build_template windows-dc
    build_template windows-mssql
    build_template webserver
    build_template linux-vuln
    ;;
esac

echo ""
echo "=== All templates built ==="
echo "Update TEMPLATES dict in services/session_manager.py with the new VMID numbers."
