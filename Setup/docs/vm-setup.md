# COCO Control VM — Setup Guide

## Proxmox VM Configuration

### General
| Setting | Value |
|---------|-------|
| VM Name | `coco-control` |
| OS | Debian 13 (Trixie) x86_64 |
| VM ID | e.g. `100` |

### System
| Setting | Value | Reason |
|---------|-------|--------|
| Machine type | `q35` | Required for PCIe + nested virt |
| BIOS | `OVMF (UEFI)` | Modern boot standard |

### CPU
| Setting | Value | Reason |
|---------|-------|--------|
| Cores | `26` | Leaves 2 cores for Proxmox host |
| Type | `host` | **Critical** — passes Intel VT-x to nested KVM |
| NUMA | enabled | Better memory locality |

### Memory
| Setting | Value |
|---------|-------|
| RAM | `58 GB` (59392 MB) |
| Ballooning | disabled |

### Disk
| Setting | Value |
|---------|-------|
| Size | `300 GB` |
| Bus | `VirtIO SCSI` |
| Cache | `Write Back` |
| Discard | enabled (if SSD) |

### Network
| Interface | Bridge | Purpose |
|-----------|--------|---------|
| `net0` | `vmbr0` | LAN access — COCO Web-GUI reachable here |
| `net1` | `vmbr1` | Internal game VLANs (isolated, no LAN route) |

---

## Nested Virtualization — Enable on Proxmox Host

Run this on the **Proxmox host** (not the VM):

```bash
# Check current status
cat /sys/module/kvm_intel/parameters/nested
# Expected: 1

# If not enabled
echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
modprobe -r kvm_intel && modprobe kvm_intel

# Verify
cat /sys/module/kvm_intel/parameters/nested
```

---

## Debian 13 Installation

1. Download Debian 13 (Trixie) netinstall ISO
2. Upload to Proxmox ISO storage (`local` or `local-lvm`)
3. Boot COCO VM from ISO
4. During install:
   - Hostname: `coco-control`
   - Minimal install (no desktop environment)
   - SSH server: **yes**
   - Standard system utilities: **yes**
5. Create user `coco` with sudo access

---

## Post-Install Network Configuration

Edit `/etc/network/interfaces` on the COCO VM:

```
# LAN interface — COCO Web-GUI accessible here
auto ens18
iface ens18 inet static
    address 192.168.118.133
    netmask 255.255.255.0
    gateway 192.168.118.1
    dns-nameservers 1.1.1.1 8.8.8.8

# Second interface for game network (managed by COCO installer)
auto ens19
iface ens19 inet manual
```

Apply and verify:
```bash
systemctl restart networking
ip addr show ens18
ping -c2 192.168.118.1
```

---

## Next Step

Once the VM is reachable via SSH, run the COCO installer:

```bash
ssh root@192.168.118.133
curl -fsSL https://raw.githubusercontent.com/youruser/coco/main/scripts/install.sh | bash
```
