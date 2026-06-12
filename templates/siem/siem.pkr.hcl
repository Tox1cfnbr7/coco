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
variable "vm_id"            { type = string; default = "9006" }
variable "vm_name"          { type = string; default = "coco-tpl-siem" }

source "proxmox-iso" "siem" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_user
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  cores    = 4
  memory   = 16384   # Elastic needs RAM
  os       = "l26"
  cpu_type = "host"
  qemu_agent = true

  # Ubuntu 22.04 LTS Server
  iso_url      = "https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
  iso_checksum = "sha256:45f873de9f8cb637345d6e66a583762730bbea30277ef7b32c9c3bd6700a32b2"
  iso_storage_pool = var.iso_storage
  unmount_iso  = true

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "virtio"
    disk_size    = "100G"
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
  boot_wait      = "5s"
  boot_command = [
    "<esc><wait>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  ssh_username           = "root"
  ssh_password           = "coco2024"
  ssh_timeout            = "90m"
  ssh_handshake_attempts = 50

  template_name        = var.vm_name
  template_description = "COCO SIEM Stack — Elasticsearch + Kibana + Wazuh + Zeek. Built: ${formatdate("YYYY-MM-DD", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.siem"]

  provisioner "shell" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",

      # Base packages
      "apt-get update -qq",
      "apt-get upgrade -y -qq",
      "apt-get install -y -qq curl wget gnupg apt-transport-https",
      "apt-get install -y -qq python3 python3-pip net-tools jq unzip",
      "apt-get install -y -qq cloud-init qemu-guest-agent",

      # Java (required by Elasticsearch)
      "apt-get install -y -qq openjdk-17-jdk",

      # ── Elasticsearch ──────────────────────────────────
      "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg",
      "echo 'deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main' > /etc/apt/sources.list.d/elastic-8.x.list",
      "apt-get update -qq",
      "apt-get install -y -qq elasticsearch",

      # Configure Elasticsearch for single-node
      "cat > /etc/elasticsearch/elasticsearch.yml << 'ESEOF'",
      "cluster.name: coco-siem",
      "node.name: siem-01",
      "network.host: 0.0.0.0",
      "http.port: 9200",
      "discovery.type: single-node",
      "xpack.security.enabled: false",
      "xpack.security.http.ssl.enabled: false",
      "ESEOF",

      # Set JVM heap (half of RAM, max 8GB)
      "sed -i 's/-Xms[0-9]*g/-Xms4g/' /etc/elasticsearch/jvm.options",
      "sed -i 's/-Xmx[0-9]*g/-Xmx4g/' /etc/elasticsearch/jvm.options",
      "systemctl enable elasticsearch",

      # ── Kibana ─────────────────────────────────────────
      "apt-get install -y -qq kibana",
      "cat > /etc/kibana/kibana.yml << 'KEOF'",
      "server.host: '0.0.0.0'",
      "server.name: 'coco-siem'",
      "elasticsearch.hosts: ['http://localhost:9200']",
      "KEOF",
      "systemctl enable kibana",

      # ── Wazuh Manager ─────────────────────────────────
      "curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg",
      "echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main' > /etc/apt/sources.list.d/wazuh.list",
      "apt-get update -qq",
      "WAZUH_MANAGER='127.0.0.1' apt-get install -y -qq wazuh-manager",
      "systemctl enable wazuh-manager",

      # ── Zeek (Network Security Monitor) ───────────────
      "echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/zeek.list",
      "curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null",
      "apt-get update -qq",
      "apt-get install -y -qq zeek || apt-get install -y -qq zeek-lts",
      "echo 'export PATH=$PATH:/opt/zeek/bin' >> /etc/profile",

      # ── Suricata ───────────────────────────────────────
      "apt-get install -y -qq suricata",
      "suricata-update update-sources 2>/dev/null || true",
      "systemctl enable suricata",

      # ── TheHive (Incident Response) ───────────────────
      # Install Cassandra first (TheHive backend)
      "echo 'deb https://downloads.apache.org/cassandra/debian 40x main' > /etc/apt/sources.list.d/cassandra.list",
      "curl -fsSL https://downloads.apache.org/cassandra/KEYS | gpg --dearmor -o /usr/share/keyrings/cassandra.gpg",
      "apt-get update -qq",
      "apt-get install -y -qq cassandra || true",

      # SSH + cloud-init
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "echo 'root:coco2024' | chpasswd",
      "systemctl enable ssh cloud-init qemu-guest-agent",

      # Sysctl tuning for Elasticsearch
      "echo 'vm.max_map_count=262144' >> /etc/sysctl.conf",
      "echo 'fs.file-max=65536' >> /etc/sysctl.conf",

      # Cleanup
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "cloud-init clean --logs",
      "dd if=/dev/zero of=/tmp/zero bs=4M 2>/dev/null || true",
      "rm -f /tmp/zero && sync"
    ]
    timeout = "3600s"
  }
}
