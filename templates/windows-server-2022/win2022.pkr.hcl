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
  default = "9001"
}
variable "vm_name" {
  type = string
  default = "coco-tpl-win2022"
}

# Windows Server 2022 Evaluation — free 180-day license, no key needed
# Official Microsoft download
variable "win_iso_url" {
  type    = string
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
  type    = string
  # SHA256 of Windows Server 2022 Eval 20348.169
  default = "sha256:3e4fa6d8507b554856fc9ca6079cc402df11a8b79344871669f0251535255325"
}

# VirtIO drivers — required for Windows to see the disk and NIC
variable "virtio_iso_url" {
  type    = string
  default = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}
variable "virtio_iso_checksum" {
  type    = string
  default = "none"
}

source "proxmox-iso" "win2022" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  cores    = 4
  sockets  = 1
  memory   = 8192
  os       = "win11"   # Proxmox OS type for Windows Server 2022
  cpu_type = "host"
  qemu_agent = true

  # Windows Server 2022 Evaluation ISO (auto downloaded)
  iso_file     = var.win_iso_file != "" ? var.win_iso_file : null
  iso_url      = var.win_iso_file != "" ? null : var.win_iso_url
  iso_checksum = var.win_iso_file != "" ? null : var.win_iso_checksum
  iso_storage_pool = var.iso_storage
  unmount_iso  = true

  # VirtIO drivers ISO (mounted as second CD-ROM)
  additional_iso_files {
    iso_url          = var.virtio_iso_url
    iso_checksum     = var.virtio_iso_checksum
    iso_storage_pool = var.iso_storage
    device           = "ide2"
    unmount          = true
  }

  # Autounattend.xml injected via virtual CD-ROM
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
    bridge   = var.network_bridge
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

  boot_wait    = "3s"
  boot_command = ["<spacebar>"]

  template_name        = var.vm_name
  template_description = "COCO Windows Server 2022 — DC + MSSQL base. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.win2022"]

  # Install VirtIO guest tools (disk + NIC drivers)
  provisioner "windows-shell" {
    inline = [
      "E:\\virtio-win-gt-x64.msi /quiet /norestart",
      "timeout /t 15 /nobreak > NUL"
    ]
    timeout = "600s"
  }

  # Install QEMU guest agent
  provisioner "windows-shell" {
    inline = [
      "E:\\guest-agent\\qemu-ga-x86_64.msi /quiet /norestart",
      "timeout /t 10 /nobreak > NUL"
    ]
    timeout = "300s"
  }

  provisioner "powershell" {
    inline = [
      # Install Windows features for AD DS
      "Install-WindowsFeature -Name AD-Domain-Services,DNS,GPMC,RSAT-AD-Tools,RSAT-DNS-Server -IncludeManagementTools -ErrorAction SilentlyContinue",

      # Install SQL Server Express (free)
      "$sqlUrl = 'https://go.microsoft.com/fwlink/?linkid=866658'",
      "Invoke-WebRequest -Uri $sqlUrl -OutFile C:\\SQLServerExpress.exe -UseBasicParsing",
      "Start-Process -FilePath C:\\SQLServerExpress.exe -ArgumentList @('/ACTION=Install','/FEATURES=SQLEngine','/INSTANCENAME=MSSQLSERVER','/SQLSVCACCOUNT=NT AUTHORITY\\NETWORK SERVICE','/SQLSYSADMINACCOUNTS=BUILTIN\\Administrators','/AGTSVCACCOUNT=NT AUTHORITY\\NETWORK SERVICE','/IACCEPTSQLSERVERLICENSETERMS','/QUIET') -Wait -NoNewWindow",
      "Remove-Item C:\\SQLServerExpress.exe -Force -ErrorAction SilentlyContinue",

      # Enable SQL Server remote connections
      "Set-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Microsoft SQL Server\\MSSQL16.MSSQLSERVER\\MSSQLServer\\SuperSocketNetLib\\Tcp' -Name 'Enabled' -Value 1 -ErrorAction SilentlyContinue",
      "Restart-Service -Name MSSQLSERVER -Force -ErrorAction SilentlyContinue",

      # Firewall rules
      "New-NetFirewallRule -Name 'MSSQL' -DisplayName 'MS SQL Server' -Protocol TCP -LocalPort 1433 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue",
      "New-NetFirewallRule -Name 'WinRM-HTTP'  -DisplayName 'WinRM HTTP'  -Protocol TCP -LocalPort 5985 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue",
      "New-NetFirewallRule -Name 'WinRM-HTTPS' -DisplayName 'WinRM HTTPS' -Protocol TCP -LocalPort 5986 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue",

      # Disable Windows Firewall (lab only)
      "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",

      # Enable RDP
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",

      # WinRM for Ansible
      "Enable-PSRemoting -Force",
      "Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
      "Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",
      "winrm set winrm/config/service/auth '@{Basic=\"true\"}'",
      "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'",

      # Install Chocolatey
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
      "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
      "choco install -y notepadplusplus 7zip sysinternals --no-progress",

      # QEMU Guest Agent service
      "Set-Service -Name QEMU-GA -StartupType Automatic -ErrorAction SilentlyContinue",
      "Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue",

      # Timezone
      "Set-TimeZone -Id 'UTC'",

      # Clean up
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path 'C:\\Temp\\*'         -Recurse -Force -ErrorAction SilentlyContinue",

      # Sysprep — generalize for cloning
      "& C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown"
    ]
    timeout = "3600s"
  }
}
