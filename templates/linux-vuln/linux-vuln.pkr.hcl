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
variable "vm_id"            { default = "9004" }
variable "iso_storage"      { default = "local" }

source "proxmox-iso" "linux-vuln" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true
  vm_id   = var.vm_id
  vm_name = "coco-tpl-linux-vuln"
  cores   = 2
  memory  = 2048
  os      = "l26"
  iso_url          = "https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
  iso_checksum     = "sha256:45f873de9f8cb637345d6e66a583762730bbea30277ef7b32c9c3bd6700a32b2"
  iso_storage_pool = var.iso_storage
  unmount_iso      = true
  disks {
    type         = "scsi"
    disk_size    = "40G"
    storage_pool = "local-lvm"
  }
  network_adapters { model = "virtio"; bridge = "vmbr0" }
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"
  http_directory = "http"
  boot_command = [
    "<esc><wait>c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait>boot<enter>"
  ]
  boot_wait    = "10s"
  ssh_username = "root"
  ssh_password = "coco2024"
  ssh_timeout  = "45m"
  template_name        = "coco-tpl-linux-vuln"
  template_description = "COCO Linux Vulnerable Services Template"
}

build {
  sources = ["source.proxmox-iso.linux-vuln"]
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -qq && apt-get upgrade -y -qq",
      "apt-get install -y -qq openssh-server vsftpd samba apache2 php nfs-kernel-server python3 python3-pip net-tools curl wget git cloud-init",
      "useradd -m -s /bin/bash devops && echo 'devops:devops123' | chpasswd",
      "useradd -m -s /bin/bash svcaccount && echo 'svcaccount:Service123!' | chpasswd",
      "echo 'root:coco2024' | chpasswd",
      "sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
      "sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "systemctl enable cloud-init",
      "apt-get clean",
      "dd if=/dev/zero of=/tmp/zero bs=1M 2>/dev/null || true && rm -f /tmp/zero && sync"
    ]
  }
}
