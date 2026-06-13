"""
COCO — VM Configuration (single source of truth)

This module is the ONLY place that defines:
  * which Packer templates exist and their fixed Proxmox VMIDs
  * which VMs make up each game mode
  * which network services are checked per VM role
  * which vulnerabilities can apply to which role
  * how flags / scoring are laid out per mode

The Proxmox VMIDs below MUST match the `vm_id` defaults in the Packer
templates (templates/<name>/<name>.pkr.hcl). They are fixed on purpose so
the backend can clone a template by VMID without any manual editing after
a build.

    template key   VMID   Packer dir                  template VM name
    -----------    ----   ------------------------    -------------------
    kali           9000   templates/kali              coco-tpl-kali
    win2022        9001   templates/windows-server-2022  coco-tpl-win2022
    dc02-ca        9002   templates/dc02-ca           coco-tpl-dc02-ca
    debian12       9003   templates/debian12          coco-tpl-debian12
    win10          9005   templates/windows-10        coco-tpl-win10
    siem           9006   templates/siem              coco-tpl-siem
"""

from models.game import GameMode

# ── Template registry ──────────────────────────────────────
# key -> Proxmox VMID of the built template (see table above)
TEMPLATES = {
    "kali":     9000,
    "win2022":  9001,
    "dc02-ca":  9002,
    "debian12": 9003,
    "win10":    9005,
    "siem":     9006,
}

# Template keys that are Windows (use RDP / WinRM rather than SSH).
WINDOWS_TEMPLATES = {"win2022", "dc02-ca", "win10"}

# Metadata shown in the admin "Templates" tab. Keys MUST match TEMPLATES
# and the directory map in templates/build-templates.sh.
TEMPLATE_META = {
    "kali":     {"label": "Kali Linux",            "role": "attacker",    "ram_gb": 8,  "disk_gb": 80},
    "debian12": {"label": "Debian 12",             "role": "web/linux",   "ram_gb": 2,  "disk_gb": 40},
    "win2022":  {"label": "Windows Server 2022",   "role": "dc/mssql",    "ram_gb": 8,  "disk_gb": 80},
    "win10":    {"label": "Windows 10",            "role": "workstation", "ram_gb": 4,  "disk_gb": 60},
    "dc02-ca":  {"label": "Win Server 2022 (CA)",  "role": "dc-ca",       "ram_gb": 8,  "disk_gb": 80},
    "siem":     {"label": "SIEM (Elastic+Wazuh)",  "role": "siem",        "ram_gb": 16, "disk_gb": 100},
}


def is_windows(template_key: str) -> bool:
    """True if a template/vm_type is a Windows image."""
    return template_key in WINDOWS_TEMPLATES


# ── VM definitions per game mode ───────────────────────────
# ip_offset = last octet of 10.<a>.<b>.<offset> inside the game VLAN.
#
# Design goals:
#   * initial_access stays LEAN (resource friendly) — Kali + 2 Linux + 1 DC
#   * heavier modes add Windows AD, MSSQL, file server, SIEM
#   * "fileserver" role reuses the win2022 template (no separate srv-file image)
GAME_VMS = {

    # ── MODE 1: Initial Access — lean, Linux-first, low resource ──
    GameMode.initial_access: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",            "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (DMZ Web App)",       "role": "web"},
        {"name": "linux01",   "template": "debian12", "team": "blue", "ip_offset": 11,
         "display": "SRV-01 (Linux Services)",    "role": "linux"},
    ],

    # ── MODE 2: Full Compromise — full enterprise AD + SIEM ──
    GameMode.full_compromise: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",            "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (DMZ Web App)",       "role": "web"},
        {"name": "dc01",      "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC / DNS)",   "role": "dc-primary"},
        {"name": "dc02",      "template": "dc02-ca",  "team": "blue", "ip_offset": 21,
         "display": "DC-02 (Secondary DC / CA)",  "role": "dc-secondary"},
        {"name": "sql01",     "template": "win2022",  "team": "blue", "ip_offset": 22,
         "display": "SRV-SQL (MSSQL Server)",     "role": "dc-mssql"},
        {"name": "linux01",   "template": "debian12", "team": "blue", "ip_offset": 31,
         "display": "SRV-DEV (Linux Services)",   "role": "linux"},
        {"name": "ws01",      "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",        "role": "workstation"},
        {"name": "siem",      "template": "siem",     "team": "blue", "ip_offset": 60,
         "display": "SIEM (Elastic / Wazuh)",     "role": "siem"},
    ],

    # ── MODE 3: Ransomware Simulation ──
    GameMode.ransomware_sim: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",            "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (Entry Point)",       "role": "web"},
        {"name": "dc01",      "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC)",         "role": "dc-primary"},
        {"name": "sql01",     "template": "win2022",  "team": "blue", "ip_offset": 22,
         "display": "SRV-SQL (MSSQL + Backups)",  "role": "dc-mssql"},
        {"name": "file01",    "template": "win2022",  "team": "blue", "ip_offset": 30,
         "display": "SRV-FILE (File Server)",     "role": "fileserver"},
        {"name": "ws01",      "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",        "role": "workstation"},
        {"name": "ws02",      "template": "win10",    "team": "blue", "ip_offset": 41,
         "display": "WS-02 (Workstation)",        "role": "workstation"},
        {"name": "siem",      "template": "siem",     "team": "blue", "ip_offset": 60,
         "display": "SIEM (Elastic / Wazuh)",     "role": "siem"},
    ],

    # ── MODE 4: Purple Team / AD CS abuse ──
    GameMode.purple_team: [
        {"name": "kali",  "template": "kali",    "team": "red",  "ip_offset": 50,
         "display": "Kali (Red Team)",                       "role": "attacker"},
        {"name": "dc01",  "template": "win2022", "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC)",                    "role": "dc-primary"},
        {"name": "dc02",  "template": "dc02-ca", "team": "blue", "ip_offset": 21,
         "display": "DC-02 (AD CS — Certificate Authority)", "role": "dc-secondary"},
        {"name": "ws01",  "template": "win10",   "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",                   "role": "workstation"},
        {"name": "siem",  "template": "siem",    "team": "blue", "ip_offset": 60,
         "display": "SIEM (Detection)",                      "role": "siem"},
    ],
}


# ── Services checked per VM role (flag-checker uptime scoring) ──
SERVICES_TO_CHECK = {
    "web":          [("http",  80),  ("https", 443)],
    "linux":        [("ssh",   22),  ("http",  80)],
    "dc-primary":   [("rdp",  3389), ("ldap",  389), ("dns", 53)],
    "dc-secondary": [("rdp",  3389), ("ldap",  389)],
    "dc-mssql":     [("rdp",  3389), ("mssql", 1433)],
    "fileserver":   [("rdp",  3389), ("smb",   445)],
    "workstation":  [("rdp",  3389)],
    "siem":         [("https", 443), ("http", 5601)],
}


# ── Default credentials per protocol (Guacamole connections) ──
DEFAULT_CREDS = {
    "rdp": ("Administrator", "Coco2024!"),
    "ssh": ("root",          "coco2024"),
}
