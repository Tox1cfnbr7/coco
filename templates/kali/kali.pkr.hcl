packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Variables ──────────────────────────────────────────────
variable "proxmox_url"      { default = "https://127.0.0.1:8006/api2/json" }
variable "proxmox_user"     { default = "root@pam" }
variable "proxmox_password" { sensitive = true }
variable "proxmox_node"     { default = "coco" }
variable "vm_id"            { default = "9000" }
variable "iso_storage"      { default = "local" }

source "proxmox-iso" "kali" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id   = var.vm_id
  vm_name = "coco-tpl-kali"
  cores   = 4
  memory  = 8192
  os      = "l26"

  # Kali 2024.1 — download ISO or use local
  iso_url          = "https://cdimage.kali.org/kali-2024.1/kali-linux-2024.1-installer-amd64.iso"
  iso_checksum     = "sha256:fa64d26b903e4a8eeb28a5b7cf43a4e4e3a8dc71ec3d9da74e3b3ad8a1f33c30"
  iso_storage_pool = var.iso_storage
  unmount_iso      = true

  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = "local-lvm"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  boot_command = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kali-preseed.cfg",
    " console-keymaps-at/keymap=us keyboard-configuration/xkb-keymap=us",
    " locale=en_US<enter>"
  ]

  http_directory = "http"
  boot_wait      = "10s"

  ssh_username = "root"
  ssh_password = "coco2024"
  ssh_timeout  = "45m"

  template_name        = "coco-tpl-kali"
  template_description = "COCO Kali Linux Attacker Template — built by Packer"
}

build {
  sources = ["source.proxmox-iso.kali"]

  # Update + install tools
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -qq",
      "apt-get upgrade -y -qq",

      # Core attacker tools
      "apt-get install -y -qq kali-tools-top10 kali-tools-windows-resources",
      "apt-get install -y -qq nmap masscan ncat netcat-openbsd",
      "apt-get install -y -qq metasploit-framework",
      "apt-get install -y -qq impacket-scripts python3-impacket",
      "apt-get install -y -qq bloodhound neo4j",
      "apt-get install -y -qq crackmapexec",
      "apt-get install -y -qq evil-winrm",
      "apt-get install -y -qq ffuf gobuster feroxbuster",
      "apt-get install -y -qq john hashcat",
      "apt-get install -y -qq responder",
      "apt-get install -y -qq ldapdomaindump",
      "apt-get install -y -qq kerbrute || pip3 install kerbrute",

      # Python tools
      "pip3 install --quiet impacket requests httpx",

      # Clean up
      "apt-get autoremove -y -qq",
      "apt-get clean",
      "echo 'root:coco2024' | chpasswd",
      "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",

      # Cloud-init setup
      "apt-get install -y -qq cloud-init",
      "systemctl enable cloud-init",

      # Zero out disk for compression
      "dd if=/dev/zero of=/tmp/zero bs=1M 2>/dev/null || true",
      "rm -f /tmp/zero",
      "sync"
    ]
  }

  # Upload COCO agent script
  provisioner "file" {
    source      = "scripts/coco-agent.sh"
    destination = "/usr/local/bin/coco-agent"
  }

  provisioner "shell" {
    inline = ["chmod +x /usr/local/bin/coco-agent"]
  }
}
