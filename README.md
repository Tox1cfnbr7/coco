```
 ██████╗  ██████╗  ██████╗  ██████╗
██╔════╝ ██╔═══██╗██╔════╝ ██╔═══██╗
██║      ██║   ██║██║      ██║   ██║
██║      ██║   ██║██║      ██║   ██║
╚██████╗ ╚██████╔╝╚██████╗ ╚██████╔╝
 ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝

        Attack & Defense Platform
```

> A self-hosted cybersecurity Attack vs. Defense platform with automated VM
> deployment, real-time service monitoring and browser-based access — no VPN
> or local VMs required. Red Team attacks, Blue Team patches and defends.

---

## Overview

COCO runs entirely on a single **Debian 13** control VM on top of **Proxmox VE 9**.
You drive everything from the web-GUI: build VM templates with Packer, create a
session, hand out join codes, and watch the scoreboard. Vulnerabilities are
injected with Ansible and players reach the machines through Apache Guacamole in
the browser.

```
Proxmox VE 9 host
└── COCO control VM (Debian 13)
    ├── COCO web-GUI + FastAPI        (https://<vm-ip>)
    ├── PostgreSQL · Redis            (state + rate limiting)
    ├── Apache Guacamole              (browser RDP/SSH)
    ├── Packer                        (builds VM templates)
    └── Ansible                       (injects vulns + places flags)
```

---

## Game modes

The web-GUI exposes four session modes (backend enum `GameMode`):

| Mode | Footprint | What it spins up |
|------|-----------|------------------|
| **Initial Access** | Lean / low-resource | Kali + 2 Debian VMs (web + linux). **100% Linux — no Windows ISO or Galaxy collections needed.** Best starting point. |
| **Full Compromise** | Heavy | Kali + Debian web + Windows AD (DC-01, DC-02/CA, MSSQL) + workstation + SIEM |
| **Ransomware Sim** | Heavy | Like Full Compromise with a file server and extra workstations |
| **Purple Team** | Medium | Kali + AD + AD CS + SIEM, detection-focused |

**Flags.** Each blue VM that matters holds a flag (`COCO{...}`). On Linux it is
written to `/flag.txt`, the web root and `/root/`. On Windows it is placed on the
Administrator Desktop (the "document to protect"). Red Team captures by reading a
flag and submitting it in the web-GUI; capturing all flags ends the session and
the Blue Team gets the **"YOU GOT HACKED"** takeover screen.

| Duration | Time limit |
|----------|-----------|
| Quick | 2 h |
| Standard | 4 h |
| Long | 8 h |
| Unlimited | none (teams can surrender) |

---

## Requirements

**Proxmox host**
- Proxmox VE 9, CPU with VT-x/VT-d, nested virtualization enabled
- Initial Access mode is light; the Windows/SIEM modes want 32 GB+ RAM and 300 GB+ disk

**COCO control VM**
- Debian 13 (Trixie), CPU type `host`, SSH enabled
- ≥ 8 GB RAM / 50 GB disk to install (more for Windows modes)

---

## Quick start

```bash
# 1. Create the Debian 13 control VM in Proxmox (see Setup/docs/vm-setup.md)
# 2. SSH in as root
ssh root@<COCO-VM-IP>

# 3. Run the installer (clones the repo, installs the full stack, reboots once
#    into the Proxmox kernel and resumes automatically)
curl -fsSL https://raw.githubusercontent.com/Tox1cfnbr7/coco/main/scripts/install.sh | bash
```

When it finishes:
- COCO web-GUI: `https://<COCO-VM-IP>`  (admin login you chose during install)
- Proxmox GUI: `https://<COCO-VM-IP>:8006`

Then in the web-GUI: **Admin → Templates → Build** the templates you need, create a
session, share the join codes.

---

## Building VM templates (ISOs)

Templates are built with Packer and have **fixed Proxmox VMIDs** that already match
the backend — no manual editing after a build:

| key | VMID | OS |
|-----|------|----|
| kali | 9000 | Kali Linux |
| win2022 | 9001 | Windows Server 2022 |
| dc02-ca | 9002 | Windows Server 2022 (AD CS) |
| debian12 | 9003 | Debian 12 |
| win10 | 9005 | Windows 10 |
| siem | 9006 | Ubuntu 22.04 (Elastic + Wazuh) |

**Linux ISOs download automatically.** The Packer files use self-validating
`file:` checksums (they fetch `SHA256SUMS`), so a new Debian/Kali/Ubuntu point
release does not break the build — only the version in `iso_url` ever needs a bump.

**Windows ISOs need staging.** Microsoft's evaluation download links rotate and
require accepting a EULA, so the reliable path is to upload the eval ISO to Proxmox
(*Datacenter → Storage → ISO Images*) and build with:

```bash
WIN_ISO_FILE=local:iso/SERVER_EVAL_x64FRE_en-us.iso \
  bash templates/build-templates.sh --template win2022
```

You can override any ISO at build time: `ISO_URL=…`, `ISO_CHECKSUM=…`,
`WIN_ISO_URL=…`, `WIN_ISO_FILE=…`.

---

## Project structure

```
coco/
├── README.md
├── scripts/install.sh              # one-command native installer (Debian 13 + PVE 9)
├── templates/                      # Packer templates (fixed VMIDs)
│   ├── build-templates.sh
│   ├── kali/  debian12/  siem/  windows-server-2022/  windows-10/  dc02-ca/
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml            # Galaxy collections (Windows roles only)
│   ├── deploy-linux.yml            # collection-free, used for all-Linux sessions
│   ├── deploy-session.yml          # full deployment (adds Windows/AD/SIEM)
│   ├── teardown-session.yml
│   └── roles/                      # common, webserver, linux-vuln, dc-*, srv-file, vulns, siem-stack, sysmon, wazuh-agent
├── web/
│   ├── backend/                    # FastAPI (routes, models, services, core)
│   └── frontend/                   # React + Vite web-GUI
└── Setup/
    ├── configs/env.example
    └── docs/                       # vm-setup.md, network.md, game-modes.md
```

---

## Status — what is verified vs. what needs your live Proxmox

This matters, so it is stated plainly:

- **Verified here:** the FastAPI backend imports and runs, the full auth →
  create-session → scoreboard → admin flow works, the React frontend builds, and
  the Linux deployment playbook (`deploy-linux.yml`) passes an Ansible syntax check
  with **no** extra collections. The **Initial Access** mode is the fully
  self-contained, tested path.
- **Needs a live Proxmox to validate end-to-end:** actual Packer template builds,
  cloning/booting VMs, Guacamole RDP/SSH sessions, and the Windows / Active
  Directory roles (`dc-primary`, `dc-mssql`, `srv-file`). Those Windows roles are
  **best-effort and intentionally guarded** (`ignore_errors`) — treat the AD modes
  as advanced and expect to iterate on them in your environment.
- The native installer (`scripts/install.sh`) is the supported path.
  `Setup/docker/docker-compose.yml` is experimental and not used.

---

## License

MIT — see [LICENSE](LICENSE)
