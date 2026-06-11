```
 ██████╗ ██████╗  ██████╗ ██████╗
██╔════╝██╔═══██╗██╔════╝██╔═══██╗
██║     ██║   ██║██║     ██║   ██║
██║     ██║   ██║██║     ██║   ██║
╚██████╗╚██████╔╝╚██████╗╚██████╔╝
 ╚═════╝ ╚═════╝  ╚═════╝ ╚═════╝

        Attack & Defense Platform
```

> A self-hosted cybersecurity Attack vs. Defense platform with automated VM deployment,
> real-time flag monitoring, and browser-based access — no VPN or local VMs required.

---

## Overview

COCO is an open-source Attack & Defense platform designed for corporate security events,
training exercises, and private CTF sessions. Red Teams attack, Blue Teams defend.
Everything runs in your browser.

```
Proxmox Host
└── COCO Control VM (Debian 13)
    ├── COCO Web-GUI        (your entry point)
    ├── Docker Stack        (API · DB · Redis · Guacamole)
    └── KVM / libvirt
        ├── VLAN 10  Active Directory Scenario
        ├── VLAN 20  Web Application Scenario
        └── VLAN 30  Database Scenario
```

---

## Game Modes

| Mode | Description | Flag Location |
|------|-------------|---------------|
| Active Directory | Windows AD + clients, patch & defend | `Desktop\flag.docx` |
| Web Application | Vulnerable web stack | `/flag.txt` |
| Database | Exposed database services | Inside DB table |

## Time Limits

| Session | Duration |
|---------|----------|
| Quick Game | 2 hours |
| Standard | 8 hours |
| Real-Life Sim | Unlimited (teams can surrender) |

---

## Requirements

### Proxmox Host
- Proxmox VE 8+ 
- CPU with Intel VT-x / VT-d (nested virtualization)
- Recommended: 32+ GB RAM, 500+ GB storage

### COCO Control VM
- OS: Debian 13 (Trixie)
- CPU: 26 vCores (type: host)
- RAM: 58 GB
- Disk: 300 GB
- Network: 1x bridge to LAN, 1x internal for game VLANs
- SSH server enabled

---

## Quick Start

```bash
# 1. Set up COCO Control VM in Proxmox (see docs/vm-setup.md)
# 2. SSH into the VM
ssh root@<COCO-VM-IP>

# 3. Run the installer
curl -fsSL https://raw.githubusercontent.com/youruser/coco/main/scripts/install.sh | bash
```

---

## Documentation

- [VM Setup Guide](docs/vm-setup.md)
- [Network Architecture](docs/network.md)
- [Packer Templates](docs/packer.md)
- [Ansible Playbooks](docs/ansible.md)
- [Game Modes](docs/game-modes.md)
- [Admin Guide](docs/admin-guide.md)

---

## Project Structure

```
coco/
├── README.md
├── docs/                        # All documentation
├── scripts/
│   └── install.sh               # One-command installer
├── docker/                      # Docker Compose stack
│   ├── docker-compose.yml
│   ├── api/                     # FastAPI backend
│   ├── frontend/                # React web-GUI
│   └── guacamole/               # Browser terminal
├── ansible/
│   ├── inventory/               # VM inventory
│   ├── playbooks/               # Deployment playbooks
│   └── roles/                   # Reusable roles
├── packer/
│   ├── ad/                      # Active Directory template
│   ├── webapp/                  # Web Application template
│   └── database/                # Database template
├── backend/                     # FastAPI source
│   ├── api/                     # Route handlers
│   ├── models/                  # DB models
│   └── services/                # Business logic
├── frontend/                    # React source
└── configs/                     # Config templates
```

---

## License

MIT License — see [LICENSE](LICENSE)
