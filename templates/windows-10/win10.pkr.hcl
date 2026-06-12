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

variable "vm_id"   { type = string; default = "9005" }
variable "vm_name" { type = string; default = "coco-tpl-win10" }

# Windows 10 Enterprise Evaluation (free 90 days)
variable "win_iso_url" {
  type    = string
  default = "https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c69161/19045.2006.220908-0225.22h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
}
variable "win_iso_checksum" {
  type    = string
  default = "sha256:ef7312733a9f5d7d351c3f8d29c716f0eba29f4d4ea0254bddc40e879c0b5d49"
}
variable "virtio_iso_url" {
  type    = string
  default = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}
variable "virtio_iso_checksum" {
  type    = string
  default = "sha256:3e7a91afc8a9e76c4b4a6c28e0e3e34b0db6e27f0fe4a52add1f07827d5c5bc7"
}

source "proxmox-iso" "win10" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  cores    = 2
  sockets  = 1
  memory   = 4096
  os       = "win11"
  cpu_type = "host"
  qemu_agent = true

  iso_url          = var.win_iso_url
  iso_checksum     = var.win_iso_checksum
  iso_storage_pool = var.iso_storage
  unmount_iso      = true

  additional_iso_files {
    iso_url          = var.virtio_iso_url
    iso_checksum     = var.virtio_iso_checksum
    iso_storage_pool = var.iso_storage
    device           = "ide2"
    unmount          = true
  }

  additional_iso_files {
    cd_files         = ["./http/autounattend-win10.xml"]
    cd_label         = "AUTOUNATTEND"
    iso_storage_pool = var.iso_storage
    device           = "ide3"
    unmount          = true
  }

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "virtio"
    disk_size    = "60G"
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

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "Coco2024!"
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "2h"

  boot_wait    = "3s"
  boot_command = ["<spacebar>"]

  template_name        = var.vm_name
  template_description = "COCO Windows 10 Workstation. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.win10"]

  provisioner "windows-shell" {
    inline  = ["E:\\virtio-win-gt-x64.msi /quiet /norestart", "timeout /t 15 /nobreak > NUL"]
    timeout = "600s"
  }

  provisioner "windows-shell" {
    inline  = ["E:\\guest-agent\\qemu-ga-x86_64.msi /quiet /norestart", "timeout /t 10 /nobreak > NUL"]
    timeout = "300s"
  }

  provisioner "powershell" {
    inline = [
      "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",
      "Enable-PSRemoting -Force",
      "Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
      "Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",
      "Set-Service -Name QEMU-GA -StartupType Automatic -ErrorAction SilentlyContinue",
      "Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue",
      "Set-TimeZone -Id 'UTC'",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "& C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown"
    ]
    timeout = "1800s"
  }
}
