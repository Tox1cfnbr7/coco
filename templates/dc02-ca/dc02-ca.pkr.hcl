packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

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
variable "iso_storage" {
  type = string
  default = "local"
}
variable "vm_id" {
  type = string
  default = "9002"
}
variable "vm_name" {
  type = string
  default = "coco-tpl-dc02-ca"
}

variable "win_iso_url" {
  default = "https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
}

# RECOMMENDED for Windows: pre-stage the eval ISO in Proxmox storage and set this
# to e.g. "local:iso/SERVER_EVAL_x64FRE_en-us.iso". Microsoft's direct eval URLs
# rotate and require accepting a EULA, so an uploaded ISO is the reliable path.
# When set, it takes precedence over win_iso_url.
variable "win_iso_file" {
  type    = string
  default = ""
}
variable "win_iso_checksum" {
  default = "sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
}
variable "virtio_iso_url" {
  default = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}
variable "virtio_iso_checksum" {
  type    = string
  default = "none"
}

source "proxmox-iso" "dc02-ca" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  cores    = 4
  memory   = 8192
  os       = "win11"
  cpu_type = "host"
  qemu_agent = true

  iso_file     = var.win_iso_file != "" ? var.win_iso_file : null
  iso_url      = var.win_iso_file != "" ? null : var.win_iso_url
  iso_checksum = var.win_iso_file != "" ? null : var.win_iso_checksum
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
    cd_files         = ["./http/autounattend.xml"]
    cd_label         = "AUTOUNATTEND"
    iso_storage_pool = var.iso_storage
    device           = "ide3"
    unmount          = true
  }

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "virtio"
    disk_size    = "80G"
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
  winrm_timeout  = "3h"
  boot_wait      = "3s"
  boot_command   = ["<spacebar>"]

  template_name        = var.vm_name
  template_description = "COCO DC-02 — Secondary DC + AD Certificate Services. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.dc02-ca"]

  provisioner "windows-shell" {
    inline  = ["E:\\virtio-win-gt-x64.msi /quiet /norestart", "timeout /t 20 /nobreak > NUL"]
    timeout = "600s"
  }

  provisioner "windows-shell" {
    inline  = ["E:\\guest-agent\\qemu-ga-x86_64.msi /quiet /norestart", "timeout /t 10 /nobreak > NUL"]
    timeout = "300s"
  }

  provisioner "powershell" {
    inline = [
      # AD DS + AD CS + DNS
      "Install-WindowsFeature -Name AD-Domain-Services,ADCS-Cert-Authority,ADCS-Web-Enrollment,DNS,GPMC,RSAT-AD-Tools,RSAT-ADCS -IncludeManagementTools",

      # Base hardening off (lab)
      "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",

      # RDP
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",

      # WinRM for Ansible
      "Enable-PSRemoting -Force",
      "Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
      "Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",

      # QEMU Agent
      "Set-Service -Name QEMU-GA -StartupType Automatic -ErrorAction SilentlyContinue",
      "Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue",

      # Chocolatey
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      "choco install -y notepadplusplus --no-progress",

      # Cleanup
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "& C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown"
    ]
    timeout = "3600s"
  }
}
