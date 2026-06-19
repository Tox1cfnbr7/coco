packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Variables (set by build-templates.sh) ──────────────────
variable "proxmox_url" {
  type = string
}
variable "proxmox_user" {
  type = string
}
variable "proxmox_password" {
  type = string
  sensitive = true
}
variable "proxmox_node" {
  type = string
}
variable "proxmox_storage" {
  type = string
  default = "local-lvm"
}
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}
variable "iso_storage" {
  type = string
  default = "local"
}

variable "vm_id" {
  type = string
  default = "9000"
}
variable "vm_name" {
  type = string
  default = "coco-tpl-kali"
}

# Kali ISO — overridable. The checksum uses Packer's self-validating "file:"
# form so it never goes stale when Kali ships a new point release: Packer
# downloads SHA256SUMS and matches the ISO filename automatically.
# Override at build time:  -var "iso_url=...  -var iso_checksum=..."
variable "iso_url" {
  type    = string
  default = "https://cdimage.kali.org/kali-2025.4/kali-linux-2025.4-installer-amd64.iso"
}
variable "iso_checksum" {
  type    = string
  default = "file:https://cdimage.kali.org/kali-2025.4/SHA256SUMS"
}

# ── Source ──────────────────────────────────────────────────
source "proxmox-iso" "kali" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id   = var.vm_id
  vm_name = var.vm_name
  cores   = 4
  sockets = 1
  memory  = 8192
  os      = "l26"
  cpu_type = "host"
  qemu_agent = true

  # Kali installer — auto downloaded by Packer, no manual upload needed
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  iso_storage_pool = var.iso_storage
  unmount_iso  = true

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "virtio"
    disk_size    = "80G"
    storage_pool = var.proxmox_storage
    discard      = true
    io_thread    = true
  }

  network_adapters {
    model  = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage

  # Preseed via HTTP server (Packer spins it up automatically)
  http_directory = "http"
  boot_wait      = "8s"
  boot_command   = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kali-preseed.cfg",
    " locale=en_US.UTF-8 keymap=us",
    " hostname=kali domain=coco.local",
    " DEBCONF_DEBUG=5",
    "<enter>"
  ]

  ssh_username         = "root"
  ssh_password         = "coco2024"
  ssh_timeout          = "90m"
  ssh_handshake_attempts = 30

  template_name        = var.vm_name
  template_description = "COCO Kali Linux 2024 — Red Team Attacker. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

# ── Build ───────────────────────────────────────────────────
build {
  sources = ["source.proxmox-iso.kali"]

  # System update + attacker tooling
  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",

      # Update
      "apt-get update -qq",
      "apt-get upgrade -y -qq",

      # Core attacker tools (kali-tools-top10 covers most things).
      # NOTE: every install below is best-effort (|| true). Kali is a rolling
      # release — package names occasionally change — and a single missing
      # or renamed package must never discard the whole VM after a multi-
      # minute install. Failures are collected and reported at the end so
      # they're visible in the Packer log without aborting the build.
      "FAILED_PKGS=''",
      "install_pkg() { apt-get install -y -qq \"$1\" || { echo \"[coco] FAILED: $1\"; FAILED_PKGS=\"$FAILED_PKGS $1\"; }; }",

      "install_pkg kali-tools-top10",
      "install_pkg kali-tools-windows-resources",

      # Additional tools commonly used in AD attacks
      "install_pkg impacket-scripts",
      "install_pkg python3-impacket",
      "install_pkg bloodhound",
      "install_pkg neo4j",
      "install_pkg evil-winrm",
      "install_pkg crackmapexec",
      "install_pkg python3-ldapdomaindump",
      "install_pkg responder",
      "install_pkg ffuf",
      "install_pkg gobuster",
      "install_pkg feroxbuster",
      "install_pkg john",
      "install_pkg hashcat",
      "install_pkg smbclient",
      "install_pkg smbmap",
      "install_pkg enum4linux-ng",
      "apt-get install -y -qq certipy-ad || pip3 install certipy-ad --quiet --break-system-packages || echo '[coco] FAILED: certipy-ad'",

      "if [ -n \"$FAILED_PKGS\" ]; then echo \"[coco] Packages that failed to install (non-fatal):$FAILED_PKGS\"; fi",

      # Install kerbrute
      "curl -sL https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 -o /usr/local/bin/kerbrute && chmod +x /usr/local/bin/kerbrute",

      # Python extras
      "pip3 install --quiet --break-system-packages requests httpx netifaces || true",

      # Cloud-init for Proxmox cloning
      "apt-get install -y -qq cloud-init qemu-guest-agent",
      "systemctl enable cloud-init qemu-guest-agent",

      # SSH root login
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "echo 'root:coco2024' | chpasswd",

      # Cleanup
      "apt-get autoremove -y -qq",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs",
      "dd if=/dev/zero of=/tmp/zero bs=4M 2>/dev/null || true",
      "rm -f /tmp/zero",
      "sync"
    ]
    timeout = "3600s"
  }
}
