"""
COCO — Session Manager v2
Extended VM roster: DC-01, DC-02 (CA), SQL, File, Web,
Linux Dev, Workstations, SIEM Stack.
"""

# ── Template VMIDs ─────────────────────────────────────────
# Update these after running build-templates.sh
TEMPLATES = {
    "kali":      9000,   # Kali Linux 2024
    "win2022":   9001,   # Windows Server 2022 (DC / MSSQL)
    "dc02-ca":   9002,   # Windows Server 2022 (DC-02 + AD CS)
    "debian12":  9003,   # Debian 12 (Web / Linux services)
    "srv-file":  9004,   # Windows Server 2022 (File Server)
    "siem":      9006,   # Ubuntu 22 (Elastic + Wazuh)
    "win10":     9005,   # Windows 10 Workstation
}

# ── VM definitions per game mode ───────────────────────────
from models.game import GameMode

GAME_VMS = {

    # ── MODE 1: Initial Access ─────────────────────────────
    # Minimal lab — web entry point into a small AD
    GameMode.initial_access: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",         "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (DMZ Web App)",    "role": "web"},
        {"name": "dc01",      "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Domain Controller)", "role": "dc-primary"},
        {"name": "ws01",      "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",     "role": "workstation"},
    ],

    # ── MODE 2: Full Compromise ────────────────────────────
    # Full enterprise AD with MSSQL, File Server, SIEM
    GameMode.full_compromise: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",              "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (DMZ Web App)",         "role": "web"},
        {"name": "dc01",      "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC / DNS)",     "role": "dc-primary"},
        {"name": "dc02",      "template": "dc02-ca",  "team": "blue", "ip_offset": 21,
         "display": "DC-02 (Secondary DC / CA)",    "role": "dc-secondary"},
        {"name": "sql01",     "template": "win2022",  "team": "blue", "ip_offset": 22,
         "display": "SRV-SQL (MSSQL Server)",       "role": "dc-mssql"},
        {"name": "file01",    "template": "srv-file", "team": "blue", "ip_offset": 30,
         "display": "SRV-FILE (File / Print)",      "role": "fileserver"},
        {"name": "linux01",   "template": "debian12", "team": "blue", "ip_offset": 31,
         "display": "SRV-DEV (Linux / Jenkins)",    "role": "linux"},
        {"name": "ws01",      "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",          "role": "workstation"},
        {"name": "ws02",      "template": "win10",    "team": "blue", "ip_offset": 41,
         "display": "WS-02 (Workstation)",          "role": "workstation"},
        {"name": "siem",      "template": "siem",     "team": "blue", "ip_offset": 60,
         "display": "SIEM (Elastic / Wazuh)",       "role": "siem"},
    ],

    # ── MODE 3: Ransomware Simulation ─────────────────────
    GameMode.ransomware_sim: [
        {"name": "kali",      "template": "kali",     "team": "red",  "ip_offset": 50,
         "display": "Kali (Attacker)",              "role": "attacker"},
        {"name": "webserver", "template": "debian12", "team": "blue", "ip_offset": 10,
         "display": "WEB-01 (Entry Point)",         "role": "web"},
        {"name": "dc01",      "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC)",           "role": "dc-primary"},
        {"name": "dc02",      "template": "dc02-ca",  "team": "blue", "ip_offset": 21,
         "display": "DC-02 (Secondary DC / CA)",    "role": "dc-secondary"},
        {"name": "sql01",     "template": "win2022",  "team": "blue", "ip_offset": 22,
         "display": "SRV-SQL (MSSQL + Backups)",    "role": "dc-mssql"},
        {"name": "file01",    "template": "srv-file", "team": "blue", "ip_offset": 30,
         "display": "SRV-FILE (File Server)",       "role": "fileserver"},
        {"name": "ws01",      "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",          "role": "workstation"},
        {"name": "ws02",      "template": "win10",    "team": "blue", "ip_offset": 41,
         "display": "WS-02 (Workstation)",          "role": "workstation"},
        {"name": "ws03",      "template": "win10",    "team": "blue", "ip_offset": 42,
         "display": "WS-03 (Workstation)",          "role": "workstation"},
        {"name": "siem",      "template": "siem",     "team": "blue", "ip_offset": 60,
         "display": "SIEM (Elastic / Wazuh)",       "role": "siem"},
    ],

    # ── MODE 4: AD Certificate Abuse ──────────────────────
    GameMode.purple_team: [
        {"name": "kali",  "template": "kali",    "team": "red",  "ip_offset": 50,
         "display": "Kali (Red Team)",              "role": "attacker"},
        {"name": "dc01",  "template": "win2022",  "team": "blue", "ip_offset": 20,
         "display": "DC-01 (Primary DC)",           "role": "dc-primary"},
        {"name": "dc02",  "template": "dc02-ca",  "team": "blue", "ip_offset": 21,
         "display": "DC-02 (AD CS — Certificate Authority)", "role": "dc-secondary"},
        {"name": "ws01",  "template": "win10",    "team": "blue", "ip_offset": 40,
         "display": "WS-01 (Workstation)",          "role": "workstation"},
        {"name": "siem",  "template": "siem",     "team": "blue", "ip_offset": 60,
         "display": "SIEM (Detection)",             "role": "siem"},
    ],
}

# Re-export everything else from the original session_manager
# (vuln pool, scoring, SessionManager class etc. stay the same)
# Only TEMPLATES and GAME_VMS are overridden here.
