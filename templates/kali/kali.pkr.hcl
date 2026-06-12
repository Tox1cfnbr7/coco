packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Variables (set by build-templates.sh) ──────────────────
variable "proxmox_url"      { type = string }
variable "proxmox_user"     { type = string }
variable "proxmox_password" { type = string; sensitive = true }
variable "proxmox_node"     { type = string }
variable "proxmox_storage"  { type = string; default = "local-lvm" }
variable "iso_storage"      { type = string; default = "local" }

variable "vm_id"   { type = string; default = "9000" }
variable "vm_name" { type = string; default = "coco-tpl-kali" }

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

  # Kali 2024.4 — auto downloaded by Packer, no manual upload needed
  iso_url      = "https://cdimage.kali.org/kali-2024.4/kali-linux-2024.4-installer-amd64.iso"
  iso_checksum = "sha256:beca4f8fd7f58eda290812f538e1323d3ba1f1a34df4b203e85de4be42525bb6"
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
    bridge = "vmbr0"
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

      # Core attacker tools (kali-tools-top10 covers most things)
      "apt-get install -y -qq kali-tools-top10",
      "apt-get install -y -qq kali-tools-windows-resources",

      # Additional tools commonly used in AD attacks
      "apt-get install -y -qq impacket-scripts python3-impacket",
      "apt-get install -y -qq bloodhound neo4j",
      "apt-get install -y -qq evil-winrm",
      "apt-get install -y -qq crackmapexec",
      "apt-get install -y -qq ldapdomaindump",
      "apt-get install -y -qq responder",
      "apt-get install -y -qq ffuf gobuster feroxbuster",
      "apt-get install -y -qq john hashcat",
      "apt-get install -y -qq smbclient smbmap",
      "apt-get install -y -qq enum4linux-ng",
      "apt-get install -y -qq certipy-ad || pip3 install certipy-ad --quiet",

      # Install kerbrute
      "curl -sL https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64 -o /usr/local/bin/kerbrute && chmod +x /usr/local/bin/kerbrute",

      # Python extras
      "pip3 install --quiet requests httpx netifaces",

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
