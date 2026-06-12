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
variable "vm_id"            { default = "9001" }
variable "iso_storage"      { default = "local" }
# Windows Server 2022 Evaluation ISO (free, 180 days)
# Download: https://go.microsoft.com/fwlink/p/?LinkID=2195280
variable "winserver_iso"    { default = "local:iso/windows-server-2022-eval.iso" }
variable "virtio_iso"       { default = "local:iso/virtio-win.iso" }

source "proxmox-iso" "windows-dc" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id   = var.vm_id
  vm_name = "coco-tpl-win-dc"
  cores   = 4
  memory  = 8192
  os      = "win11"   # Windows Server 2022

  iso_file = var.winserver_iso
  additional_iso_files {
    cd_files    = ["autounattend.xml"]
    cd_label    = "Unattend"
    iso_storage_pool = var.iso_storage
  }
  additional_iso_files {
    iso_file = var.virtio_iso
  }
  unmount_iso = true

  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = "local-lvm"
    discard      = true
    ssd          = true
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "Coco2024!"
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "60m"

  boot_wait = "5s"

  template_name        = "coco-tpl-win-dc"
  template_description = "COCO Windows Server 2022 DC Template — built by Packer"
}

build {
  sources = ["source.proxmox-iso.windows-dc"]

  # Install VirtIO drivers
  provisioner "windows-shell" {
    inline = [
      "E:\\virtio-win-guest-tools.exe /S",
      "timeout /t 30"
    ]
  }

  # Windows updates + features
  provisioner "powershell" {
    inline = [
      # Install AD DS + DNS + RSAT tools
      "Install-WindowsFeature -Name AD-Domain-Services,DNS,RSAT-AD-Tools,RSAT-DNS-Server -IncludeManagementTools",
      "Install-WindowsFeature -Name GPMC",

      # Install chocolatey for tools
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      "choco install -y notepadplusplus 7zip sysinternals",

      # Enable WinRM for Ansible
      "Enable-PSRemoting -Force",
      "Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
      "Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",
      "winrm set winrm/config/service/auth '@{Basic=\"true\"}'",

      # Enable RDP
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",

      # Set timezone
      "Set-TimeZone -Id 'UTC'",

      # Disable Windows Firewall (lab environment)
      "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",

      # Cloud-init equivalent for Proxmox
      "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Netlogon\\Parameters' -Name 'RequireSignOrSeal' -Value 0",

      # Sysprep for template
      "C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown"
    ]
  }
}
