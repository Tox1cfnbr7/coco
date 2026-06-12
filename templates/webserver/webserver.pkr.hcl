packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url"      { default = "https://127.0.0.1:8006/api2/json" }
variable "proxmox_user"     { default = "root@pam" }
variable "proxmox_password" { sensitive = true }
variable "proxmox_node"     { default = "coco" }
variable "vm_id"            { default = "9003" }
variable "iso_storage"      { default = "local" }

source "proxmox-iso" "webserver" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id   = var.vm_id
  vm_name = "coco-tpl-webserver"
  cores   = 2
  memory  = 2048
  os      = "l26"

  iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
  iso_checksum     = "sha256:013f5b44670d81280b5b1bc02455842b250df3f0c5f8fd0626b097f9ca22be3f"
  iso_storage_pool = var.iso_storage
  unmount_iso      = true

  disks {
    type         = "scsi"
    disk_size    = "40G"
    storage_pool = "local-lvm"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  http_directory = "http"
  boot_command = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/debian-preseed.cfg",
    " console-keymaps-at/keymap=us locale=en_US<enter>"
  ]
  boot_wait = "8s"

  ssh_username = "root"
  ssh_password = "coco2024"
  ssh_timeout  = "30m"

  template_name        = "coco-tpl-webserver"
  template_description = "COCO Vulnerable Web Server Template — built by Packer"
}

build {
  sources = ["source.proxmox-iso.webserver"]

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -qq",
      "apt-get upgrade -y -qq",

      # Web stack
      "apt-get install -y -qq apache2 php php-mysql php-curl php-gd php-xml libapache2-mod-php",
      "apt-get install -y -qq mariadb-server",
      "apt-get install -y -qq git curl wget unzip",

      # Enable Apache mods
      "a2enmod rewrite",

      # Install DVWA (Damn Vulnerable Web Application)
      "git clone --depth 1 https://github.com/digininja/DVWA /var/www/html/dvwa",
      "cp /var/www/html/dvwa/config/config.inc.php.dist /var/www/html/dvwa/config/config.inc.php",
      "sed -i \"s/'db_password' => 'p@ssw0rd'/'db_password' => 'dvwa'/\" /var/www/html/dvwa/config/config.inc.php",
      "sed -i \"s/\\$_DVWA\\[ 'default_security_level' \\] = 'impossible';/\\$_DVWA[ 'default_security_level' ] = 'low';/\" /var/www/html/dvwa/config/config.inc.php",
      "chown -R www-data:www-data /var/www/html/dvwa",
      "chmod -R 755 /var/www/html/dvwa",

      # Create custom vulnerable login app
      "mkdir -p /var/www/html/corp",
      "mysql -e \"CREATE DATABASE corp; CREATE USER 'corp'@'localhost' IDENTIFIED BY 'corp123'; GRANT ALL ON corp.* TO 'corp'@'localhost';\"",

      # Cloud-init
      "apt-get install -y -qq cloud-init",
      "systemctl enable cloud-init",
      "echo 'root:coco2024' | chpasswd",
      "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",

      # Cleanup
      "apt-get clean",
      "dd if=/dev/zero of=/tmp/zero bs=1M 2>/dev/null || true",
      "rm -f /tmp/zero && sync"
    ]
  }

  # Upload custom corp app
  provisioner "file" {
    source      = "http/corp-app/"
    destination = "/var/www/html/corp/"
  }
}
