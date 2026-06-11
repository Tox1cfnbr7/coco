# COCO Game Modes

## Active Directory

### Scenario
A simulated corporate Windows environment. Blue Team receives a Windows Server 2022
Domain Controller and a Windows 10 client with intentional misconfigurations.
Red Team attacks from a Kali Linux VM.

### VMs
| VM | OS | IP | Role |
|----|----|----|------|
| `win-dc-01` | Windows Server 2022 | 10.10.10.10 | Domain Controller, DNS, DHCP |
| `win-client-01` | Windows 10 | 10.10.10.20 | Domain member — flag on Desktop |
| `kali-red` | Kali Linux 2024 | 10.10.10.30 | Red Team attacker |

### Flag
- Location: `C:\Users\Administrator\Desktop\flag.docx`
- Content: A Word document with a secret capture code inside
- Red Team win: Submit the flag code via COCO Web-GUI
- Blue Team win: Prevent capture until the game timer expires

### Pre-configured Vulnerabilities (Blue must find and patch)
- SMB signing disabled
- Kerberoastable service accounts (SPN set on weak accounts)
- AS-REP Roasting enabled (no pre-auth required on domain accounts)
- Weak domain password policy (min 4 chars, no complexity)
- RDP exposed on all machines with weak local admin credentials
- Password stored in SYSVOL via GPP (Group Policy Preferences)
- LLMNR/NBT-NS enabled (enables Responder attacks)

---

## Web Application

### VMs
| VM | OS | IP | Role |
|----|----|----|------|
| `web-server` | Debian 12 | 10.10.20.10 | Vulnerable web application |
| `kali-red` | Kali Linux | 10.10.20.30 | Red Team attacker |

### Flag
- Location: `/flag.txt` on the web server
- Pre-configured vulnerabilities: SQLi, LFI, RCE, IDOR

---

## Database

### VMs
| VM | OS | IP | Role |
|----|----|----|------|
| `db-server` | Ubuntu 22.04 | 10.10.30.10 | MySQL with exposed credentials |
| `kali-red` | Kali Linux | 10.10.30.30 | Red Team attacker |

### Flag
- Location: Table `flags`, column `secret` in MySQL database
- Pre-configured vulnerabilities: Exposed port 3306, weak root password, SQL injection in frontend

---

## Time Limits

| Mode | Duration | Notes |
|------|----------|-------|
| Quick Game | 2 hours | Ideal for demos and short events |
| Standard | 8 hours | Full training day |
| Real-Life Sim | Unlimited | Teams surrender via Web-GUI |

---

## Win / Lose Conditions

### Red Team wins
- Captures the flag and submits the correct code via COCO Web-GUI
- Blue Team screen shows: red overlay, skull, "YOU GOT HACKED"
- All game VMs are automatically shut down

### Blue Team wins
- Game timer expires without Red Team capturing the flag
- Blue Team screen shows: victory screen
- Session is archived with patch log

### Surrender
- Available in Real-Life Sim mode only
- Either team can trigger via Web-GUI
- Requires confirmation from team leader
