packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url"      { type = string }
variable "proxmox_user"     { type = string }
variable "proxmox_password" { type = string; sensitive = true }
variable "proxmox_node"     { type = string }
variable "proxmox_storage"  { type = string; default = "local-lvm" }
variable "iso_storage"      { type = string; default = "local" }

variable "vm_id"   { type = string; default = "9003" }
variable "vm_name" { type = string; default = "coco-tpl-debian12" }

# Debian 12 netinst. We point at the permanent /archive/ path (the /current/
# symlink moves with every point release, which breaks pinned filenames).
# The "file:" checksum auto-resolves from SHA256SUMS, so bumping the version
# only requires changing iso_url. Override:  -var "iso_url=..."
variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/cdimage/archive/12.11.0/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
}
variable "iso_checksum" {
  type    = string
  default = "file:https://cdimage.debian.org/cdimage/archive/12.11.0/amd64/iso-cd/SHA256SUMS"
}

source "proxmox-iso" "debian12" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  cores    = 2
  sockets  = 1
  memory   = 2048
  os       = "l26"
  cpu_type = "host"
  qemu_agent = true

  # Debian 12 netinst — small ISO, rest downloaded during install
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  iso_storage_pool = var.iso_storage
  unmount_iso  = true

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "virtio"
    disk_size    = "40G"
    storage_pool = var.proxmox_storage
    discard      = true
    io_thread    = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage

  http_directory = "http"
  boot_wait      = "8s"
  boot_command   = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/debian12-preseed.cfg",
    " locale=en_US.UTF-8 keymap=us",
    " hostname=debian12 domain=coco.local",
    "<enter>"
  ]

  ssh_username           = "root"
  ssh_password           = "coco2024"
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 30

  template_name        = var.vm_name
  template_description = "COCO Debian 12 Base — Web/Linux Service VM. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.debian12"]

  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -qq",
      "apt-get upgrade -y -qq",

      # Base services (web + vuln services)
      "apt-get install -y -qq apache2 php php-mysql php-curl php-gd libapache2-mod-php",
      "apt-get install -y -qq mariadb-server",
      "apt-get install -y -qq vsftpd samba nfs-kernel-server",
      "apt-get install -y -qq openssh-server python3 python3-pip",
      "apt-get install -y -qq curl wget git unzip net-tools",
      "apt-get install -y -qq sudo",

      # DVWA — Damn Vulnerable Web Application
      "git clone --depth 1 https://github.com/digininja/DVWA /var/www/html/dvwa 2>/dev/null || true",
      "if [[ -d /var/www/html/dvwa ]]; then",
      "  cp /var/www/html/dvwa/config/config.inc.php.dist /var/www/html/dvwa/config/config.inc.php",
      "  sed -i \"s/'db_password' => 'p@ssw0rd'/'db_password' => 'dvwa'/\" /var/www/html/dvwa/config/config.inc.php",
      "  sed -i \"s/low/low/g\" /var/www/html/dvwa/config/config.inc.php",
      "  chown -R www-data:www-data /var/www/html/dvwa",
      "fi",

      # Enable Apache modules
      "a2enmod rewrite",

      # Create vulnerable users for priv-esc scenarios
      "useradd -m -s /bin/bash devops   && echo 'devops:devops123'       | chpasswd",
      "useradd -m -s /bin/bash svcacct  && echo 'svcacct:Service123!'    | chpasswd",

      # Cloud-init + QEMU agent
      "apt-get install -y -qq cloud-init qemu-guest-agent",
      "systemctl enable cloud-init qemu-guest-agent ssh apache2",

      # Root login via SSH
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/'   /etc/ssh/sshd_config",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "echo 'root:coco2024' | chpasswd",

      # Cleanup
      "apt-get autoremove -y -qq",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs",
      "dd if=/dev/zero of=/tmp/zero bs=4M 2>/dev/null || true",
      "rm -f /tmp/zero && sync"
    ]
    timeout = "1800s"
  }
}
