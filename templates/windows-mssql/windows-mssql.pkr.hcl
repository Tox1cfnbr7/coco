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
variable "vm_id"            { default = "9002" }
variable "winserver_iso"    { default = "local:iso/windows-server-2022-eval.iso" }
variable "virtio_iso"       { default = "local:iso/virtio-win.iso" }
variable "iso_storage"      { default = "local" }

source "proxmox-iso" "windows-mssql" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true
  vm_id   = var.vm_id
  vm_name = "coco-tpl-win-mssql"
  cores   = 4
  memory  = 8192
  os      = "win11"
  iso_file = var.winserver_iso
  additional_iso_files {
    cd_files = ["../windows-dc/autounattend.xml"]
    cd_label = "Unattend"
    iso_storage_pool = var.iso_storage
  }
  additional_iso_files { iso_file = var.virtio_iso }
  unmount_iso = true
  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = "local-lvm"
    discard      = true
  }
  network_adapters { model = "virtio"; bridge = "vmbr0" }
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "Coco2024!"
  winrm_use_ssl  = false
  winrm_insecure = true
  winrm_timeout  = "60m"
  boot_wait      = "5s"
  template_name        = "coco-tpl-win-mssql"
  template_description = "COCO Windows Server 2022 MSSQL Template"
}

build {
  sources = ["source.proxmox-iso.windows-mssql"]
  provisioner "windows-shell" {
    inline = ["E:\\virtio-win-guest-tools.exe /S", "timeout /t 30"]
  }
  provisioner "powershell" {
    inline = [
      "Enable-PSRemoting -Force",
      "Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true",
      "Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $true",
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0",
      "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'",
      "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False",
      "$url='https://go.microsoft.com/fwlink/?linkid=866658'",
      "Invoke-WebRequest -Uri $url -OutFile C:\\SQLExpress.exe",
      "Start-Process C:\\SQLExpress.exe -ArgumentList '/ACTION=Install /FEATURES=SQLEngine /INSTANCENAME=MSSQLSERVER /SQLSVCACCOUNT=\"NT AUTHORITY\\NETWORK SERVICE\" /SQLSYSADMINACCOUNTS=\"BUILTIN\\Administrators\" /AGTSVCACCOUNT=\"NT AUTHORITY\\NETWORK SERVICE\" /IACCEPTSQLSERVERLICENSETERMS /QUIET' -Wait",
      "Remove-Item C:\\SQLExpress.exe -Force",
      "netsh advfirewall firewall add rule name='MSSQL' protocol=TCP dir=in localport=1433 action=allow",
      "C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown"
    ]
  }
}
