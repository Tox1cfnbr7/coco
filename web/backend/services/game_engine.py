"""
COCO — Game Engine Service
Orchestrates the full lifecycle of a game session:
  1. Create VLANs on Proxmox
  2. Clone VM templates
  3. Configure VMs via Ansible
  4. Register VMs in Guacamole
  5. Teardown on game end
"""

import asyncio
import secrets
import subprocess
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy.orm import Session

from services.proxmox import get_proxmox
from models.game import Game, VM, GameEvent, GameStatus, VMStatus
from core.config import get_settings

settings = get_settings()

# VM template IDs — set these after Packer builds the templates
TEMPLATES = {
    "kali":       100,  # Kali Linux attacker
    "win-dc":     101,  # Windows Server 2022 AD DC
    "win-client": 102,  # Windows 10 domain member
    "webserver":  103,  # Debian vulnerable web server
    "db-server":  104,  # Ubuntu vulnerable database
}

# VM definitions per game mode
GAME_VMS = {
    "active_directory": [
        {"name": "kali-red",     "template": "kali",       "team": "red",  "ip_offset": 30},
        {"name": "win-dc-01",    "template": "win-dc",     "team": "blue", "ip_offset": 10},
        {"name": "win-client-01","template": "win-client", "team": "blue", "ip_offset": 20},
    ],
    "web_application": [
        {"name": "kali-red",    "template": "kali",      "team": "red",  "ip_offset": 30},
        {"name": "webserver",   "template": "webserver", "team": "blue", "ip_offset": 10},
    ],
    "database": [
        {"name": "kali-red",   "template": "kali",      "team": "red",  "ip_offset": 30},
        {"name": "db-server",  "template": "db-server", "team": "blue", "ip_offset": 10},
    ],
}


class GameEngine:

    def __init__(self, db: Session):
        self.db  = db
        self.pve = get_proxmox()

    # ── Start game ────────────────────────────────────────────
    async def start_game(self, game: Game) -> bool:
        try:
            self._event(game, "game_starting", "Provisioning infrastructure...")

            # 1. Assign VLAN ID from game ID
            vlan_id = 100 + (game.id % 900)
            network_cidr = f"10.{vlan_id // 256}.{vlan_id % 256}.0/24"
            game.vlan_id      = vlan_id
            game.network_cidr = network_cidr
            self.db.commit()

            # 2. Clone VMs
            vm_defs = GAME_VMS.get(game.mode, [])
            created_vms = []

            for vm_def in vm_defs:
                vmid = await self.pve.next_vmid()
                vm_name = f"coco-g{game.id}-{vm_def['name']}"
                template_id = TEMPLATES[vm_def["template"]]
                ip = f"10.{vlan_id // 256}.{vlan_id % 256}.{vm_def['ip_offset']}"

                # Create DB record
                vm = VM(
                    game_id    = game.id,
                    name       = vm_def["name"],
                    vm_type    = vm_def["template"],
                    team_type  = vm_def["team"],
                    ip_address = ip,
                    status     = VMStatus.creating,
                    proxmox_vmid = vmid,
                )
                self.db.add(vm)
                self.db.commit()
                created_vms.append((vm, template_id, vmid, vm_name, ip))

                self._event(game, "vm_cloning", f"Cloning {vm_def['name']} (vmid {vmid})")

            # 3. Clone all VMs in parallel
            clone_tasks = [
                self.pve.clone_vm(tid, vmid, name)
                for (_, tid, vmid, name, _) in created_vms
            ]
            upids = await asyncio.gather(*clone_tasks, return_exceptions=True)

            # 4. Wait for clones to finish
            for (vm, _, vmid, name, ip), upid in zip(created_vms, upids):
                if isinstance(upid, Exception):
                    vm.status = VMStatus.error
                    self.db.commit()
                    continue

                ok = await self.pve.wait_for_task(upid, timeout=180)
                if not ok:
                    vm.status = VMStatus.error
                    self.db.commit()
                    continue

                # Set static IP via cloud-init
                await self.pve.set_vm_config(vmid, {
                    "ipconfig0": f"ip={ip}/24,gw=10.{vm.proxmox_vmid // 256}.{vm.proxmox_vmid % 256}.1",
                    "nameserver": "1.1.1.1",
                })

            # 5. Start all VMs
            for (vm, _, vmid, _, _) in created_vms:
                if vm.status != VMStatus.error:
                    await self.pve.start_vm(vmid)
                    vm.status = VMStatus.running
                    self.db.commit()

            # 6. Run Ansible playbooks
            await self._run_ansible(game)

            # 7. Register in Guacamole
            for (vm, _, vmid, _, ip) in created_vms:
                if vm.status == VMStatus.running:
                    guac_id = self._register_guacamole(vm, ip)
                    vm.guacamole_id = guac_id
                    self.db.commit()

            # 8. Mark game as running
            game.status     = GameStatus.running
            game.started_at = datetime.now(timezone.utc)
            self.db.commit()

            self._event(game, "game_started", f"Game running — {len(created_vms)} VMs provisioned")
            return True

        except Exception as e:
            self._event(game, "game_error", str(e))
            return False

    # ── Stop game ─────────────────────────────────────────────
    async def stop_game(self, game: Game) -> None:
        self._event(game, "game_stopping", "Shutting down VMs...")

        vms = self.db.query(VM).filter(VM.game_id == game.id).all()
        shutdown_tasks = []
        for vm in vms:
            if vm.proxmox_vmid and vm.status == VMStatus.running:
                shutdown_tasks.append(self.pve.stop_vm(vm.proxmox_vmid))
                vm.status = VMStatus.stopped
        self.db.commit()

        if shutdown_tasks:
            await asyncio.gather(*shutdown_tasks, return_exceptions=True)

        # Delete VMs after short delay
        await asyncio.sleep(5)
        for vm in vms:
            if vm.proxmox_vmid:
                try:
                    await self.pve.delete_vm(vm.proxmox_vmid)
                except Exception:
                    pass

        game.status   = GameStatus.ended
        game.ended_at = datetime.now(timezone.utc)
        self.db.commit()
        self._event(game, "game_ended", "All VMs deleted")

    # ── Ansible ───────────────────────────────────────────────
    async def _run_ansible(self, game: Game) -> None:
        playbook = f"{settings.coco_repo_dir}/ansible/playbooks/{game.mode}.yml"
        inventory = self._build_inventory(game)
        inv_file  = f"/tmp/coco-inventory-{game.id}.ini"

        with open(inv_file, "w") as f:
            f.write(inventory)

        cmd = [
            "ansible-playbook", playbook,
            "-i", inv_file,
            "--extra-vars", f"flag_value={game.flag_value} game_id={game.id}",
            "--timeout", "60",
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=300)
            if proc.returncode != 0:
                self._event(game, "ansible_warn", f"Ansible exited {proc.returncode}: {stderr.decode()[:200]}")
        except Exception as e:
            self._event(game, "ansible_warn", f"Ansible failed: {e}")

    def _build_inventory(self, game: Game) -> str:
        vms = self.db.query(VM).filter(VM.game_id == game.id).all()
        lines = ["[all]"]
        for vm in vms:
            if vm.ip_address:
                user = "Administrator" if "win" in vm.vm_type else "root"
                lines.append(f"{vm.name} ansible_host={vm.ip_address} ansible_user={user}")
        lines += [
            "\n[red]",
            *[f"{vm.name}" for vm in vms if vm.team_type == "red"],
            "\n[blue]",
            *[f"{vm.name}" for vm in vms if vm.team_type == "blue"],
        ]
        return "\n".join(lines)

    # ── Guacamole ─────────────────────────────────────────────
    def _register_guacamole(self, vm: VM, ip: str) -> str:
        """
        Adds connection to /etc/guacamole/user-mapping.xml
        Returns a connection ID string.
        """
        import xml.etree.ElementTree as ET

        xml_path = "/etc/guacamole/user-mapping.xml"
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
        except Exception:
            return ""

        protocol = "rdp" if "win" in vm.vm_type else "ssh"
        conn_id  = f"game{vm.game_id}-{vm.name}"

        for auth in root.findall("authorize"):
            conn = ET.SubElement(auth, "connection")
            conn.set("name", conn_id)
            proto = ET.SubElement(conn, "protocol")
            proto.text = protocol

            params = {
                "hostname": ip,
                "port":     "3389" if protocol == "rdp" else "22",
                "username": "Administrator" if protocol == "rdp" else "root",
                "password": "Coco2024!",
                "ignore-cert": "true",
                "security": "nla" if protocol == "rdp" else "",
            }
            for k, v in params.items():
                if v:
                    p = ET.SubElement(conn, "param")
                    p.set("name", k)
                    p.text = v

        tree.write(xml_path)
        return conn_id

    # ── Helper ────────────────────────────────────────────────
    def _event(self, game: Game, event_type: str, detail: str) -> None:
        ev = GameEvent(
            game_id    = game.id,
            event_type = event_type,
            detail     = detail,
        )
        self.db.add(ev)
        self.db.commit()
