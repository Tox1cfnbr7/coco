"""
COCO — Session Manager
Handles the full lifecycle of a game session:
  1. Deploy VMs from Proxmox templates
  2. Configure network (VLAN isolation)
  3. Inject random vulnerabilities via Ansible
  4. Register terminals in Guacamole
  5. Run flag checker (background task)
  6. Teardown everything on session kill
"""

import asyncio
import random
import secrets
import socket
import json
import os
from datetime import datetime, timezone, timedelta
from typing import Optional
from sqlalchemy.orm import Session

from services.vm_config import (
    TEMPLATES, GAME_VMS, SERVICES_TO_CHECK, DEFAULT_CREDS,
    is_windows,
)
from services.proxmox import get_proxmox
from models.game import (
    Game, Team, VM, GameEvent, ServiceCheck, CapturedFlag,
    GameStatus, VMStatus, GameMode
)
from core.config import get_settings

settings = get_settings()


# ── Vulnerability pool ─────────────────────────────────────
VULN_POOL = {
    "initial_access": [
        "webserver_sqli",
        "webserver_rce_upload",
        "webserver_lfi",
        "smb_anonymous_read",
        "vpn_default_creds",
    ],
    "lateral_movement": [
        "ad_kerberoastable_svc",
        "ad_asrep_roasting",
        "ad_password_spray",
        "mssql_xp_cmdshell",
        "smb_signing_disabled",
    ],
    "privesc": [
        "win_unquoted_service",
        "win_weak_gpo",
        "linux_suid_bash",
        "linux_sudo_nopasswd",
        "mssql_sa_weak_password",
    ],
    "persistence": [
        "ad_krbtgt_old",
        "scheduled_task_writable",
        "registry_autorun",
    ],
}

VULNS_PER_CATEGORY = {
    "easy":   1,
    "medium": 2,
    "hard":   3,
}

# ── Scoring constants ───────────────────────────────────────
POINTS = {
    "service_up_per_check":   10,   # Blue team per service per check
    "service_down_per_check": -50,  # Blue team per service down
    "initial_access":         100,
    "lateral_movement":       200,
    "domain_admin":           300,
    "data_exfil":             500,
    "persistence":            200,
    "detection_bonus":        500,  # Blue team detects + blocks Red
}

# NOTE: SERVICES_TO_CHECK and DEFAULT_CREDS are imported from vm_config
# (single source of truth) — do not redefine them here.


class SessionManager:

    def __init__(self, db: Session):
        self.db  = db
        self.pve = get_proxmox()

    # ═══════════════════════════════════════════════════════
    # START SESSION
    # ═══════════════════════════════════════════════════════
    async def start_session(self, game: Game) -> bool:
        try:
            game.status = GameStatus.provisioning
            self.db.commit()
            self._event(game, "session_starting", "Provisioning infrastructure...")

            # 1. Assign VLAN
            vlan_id = 100 + (game.id % 900)
            a, b    = vlan_id // 256, vlan_id % 256
            game.vlan_id      = vlan_id
            game.network_cidr = f"10.{a}.{b}.0/24"
            self.db.commit()

            # 2. Select random vulns
            selected_vulns = self._select_vulns(game.vuln_difficulty)
            self._event(game, "vulns_selected",
                        f"{len(selected_vulns)} vulnerabilities selected (hidden from teams)")

            # 3. Setup flags config
            game.flags_config = self._build_flags_config(game.mode)
            self.db.commit()

            # 4. Get teams
            red_team  = next((t for t in game.teams if t.type == "red"),  None)
            blue_team = next((t for t in game.teams if t.type == "blue"), None)

            # 5. Clone VMs
            vm_defs = GAME_VMS.get(game.mode, [])
            vm_records = []

            for vm_def in vm_defs:
                template_id = TEMPLATES.get(vm_def["template"])
                if not template_id:
                    self._event(game, "vm_warn",
                                f"Template not found for {vm_def['template']} — skipping")
                    continue

                vmid   = await self.pve.next_vmid()
                a, b   = vlan_id // 256, vlan_id % 256
                ip     = f"10.{a}.{b}.{vm_def['ip_offset']}"
                name   = f"coco-g{game.id}-{vm_def['name']}"
                team   = red_team if vm_def["team"] == "red" else blue_team

                vm = VM(
                    game_id      = game.id,
                    team_id      = team.id if team else None,
                    name         = vm_def["name"],
                    display_name = vm_def["display"],
                    vm_type      = vm_def["template"],
                    role         = vm_def["role"],
                    team_type    = vm_def["team"],
                    ip_address   = ip,
                    status       = VMStatus.creating,
                    proxmox_vmid = vmid,
                    injected_vulns = [
                        v for v in selected_vulns
                        if self._vuln_applies_to_role(v, vm_def["role"])
                    ],
                )
                self.db.add(vm)
                self.db.commit()
                vm_records.append((vm, template_id, vmid, name, ip))
                self._event(game, "vm_queued", f"Queued: {vm_def['display']} → {ip}")

            # 6. Clone all VMs (parallel)
            self._event(game, "vm_cloning", f"Cloning {len(vm_records)} VMs...")
            clone_tasks = [
                self.pve.clone_vm(tid, vmid, name)
                for (_, tid, vmid, name, _) in vm_records
            ]
            upids = await asyncio.gather(*clone_tasks, return_exceptions=True)

            # 7. Wait for clones + configure
            for (vm, _, vmid, name, ip), upid in zip(vm_records, upids):
                if isinstance(upid, Exception):
                    vm.status = VMStatus.error
                    self.db.commit()
                    self._event(game, "vm_error", f"{vm.name}: clone failed: {upid}")
                    continue

                ok = await self.pve.wait_for_task(str(upid), timeout=300)
                if not ok:
                    vm.status = VMStatus.error
                    self.db.commit()
                    self._event(game, "vm_error", f"{vm.name}: clone task failed")
                    continue

                # Cloud-init network config
                await self.pve.set_vm_config(vmid, {
                    "ipconfig0": f"ip={ip}/24,gw=10.{a}.{b}.1",
                    "nameserver": f"10.{a}.{b}.20",   # DC is DNS
                    "searchdomain": "corp.coco.local",
                })
                self._event(game, "vm_configured", f"{vm.display_name} configured at {ip}")

            # 8. Start all VMs
            self._event(game, "vm_starting", "Starting VMs...")
            for (vm, _, vmid, _, _) in vm_records:
                if vm.status != VMStatus.error:
                    await self.pve.start_vm(vmid)
                    vm.status = VMStatus.running
                    self.db.commit()

            # 9. Wait for VMs to boot (approx)
            self._event(game, "vm_booting", "Waiting for VMs to boot (60s)...")
            await asyncio.sleep(60)

            # 10. Run Ansible (inject vulns + configure roles)
            self._event(game, "ansible_running", "Injecting vulnerabilities via Ansible...")
            await self._run_ansible(game, vm_records, selected_vulns)

            # 11. Register Guacamole connections
            self._event(game, "guacamole_setup", "Setting up terminal access...")
            for (vm, _, _, _, ip) in vm_records:
                if vm.status == VMStatus.running:
                    guac_id = self._register_guacamole(vm, ip)
                    vm.guacamole_id = guac_id
                    self.db.commit()

            # 12. Mark running
            game.status     = GameStatus.running
            game.started_at = datetime.now(timezone.utc)
            self.db.commit()

            running_count = sum(1 for (vm, *_) in vm_records if vm.status == VMStatus.running)
            self._event(game, "session_started",
                        f"Session live — {running_count}/{len(vm_records)} VMs running")
            return True

        except Exception as e:
            game.status = GameStatus.error
            self.db.commit()
            self._event(game, "session_error", f"Fatal error: {str(e)[:500]}")
            return False

    # ═══════════════════════════════════════════════════════
    # KILL SESSION
    # ═══════════════════════════════════════════════════════
    async def kill_session(self, game: Game, reason: str = "admin_kill") -> None:
        self._event(game, "session_killing", f"Killing session: {reason}")
        game.status = GameStatus.ended

        vms = self.db.query(VM).filter(VM.game_id == game.id).all()

        # Stop all VMs in parallel
        stop_tasks = []
        for vm in vms:
            if vm.proxmox_vmid and vm.status == VMStatus.running:
                stop_tasks.append(self.pve.stop_vm(vm.proxmox_vmid))
                vm.status = VMStatus.stopped
        self.db.commit()

        if stop_tasks:
            await asyncio.gather(*stop_tasks, return_exceptions=True)

        await asyncio.sleep(8)

        # Delete VMs
        for vm in vms:
            if vm.proxmox_vmid:
                try:
                    await self.pve.delete_vm(vm.proxmox_vmid)
                except Exception:
                    pass

        # Remove Guacamole connections
        self._cleanup_guacamole(game.id)

        game.ended_at = datetime.now(timezone.utc)
        self.db.commit()
        self._event(game, "session_killed", "All VMs deleted, session terminated")

    # ═══════════════════════════════════════════════════════
    # FLAG CHECKER (runs as background task every 5min)
    # ═══════════════════════════════════════════════════════
    async def run_flag_checker(self, game: Game) -> dict:
        """
        Called by the background scheduler.
        Checks all services, updates scores + downtime.
        Returns summary dict.
        """
        results = {"checked": 0, "up": 0, "down": 0, "downtime_penalties": []}

        vms = self.db.query(VM).filter(
            VM.game_id == game.id,
            VM.team_type == "blue",
            VM.status == VMStatus.running,
        ).all()

        blue_team = next((t for t in game.teams if t.type == "blue"), None)
        if not blue_team:
            return results

        for vm in vms:
            services = SERVICES_TO_CHECK.get(vm.role, [("ssh", 22)])
            for service_name, port in services:
                reachable, latency = await self._check_service(vm.ip_address, port)

                check = ServiceCheck(
                    game_id   = game.id,
                    vm_id     = vm.id,
                    team_id   = blue_team.id,
                    service   = f"{vm.name}:{service_name}",
                    reachable = reachable,
                    latency_ms = latency,
                )
                self.db.add(check)
                results["checked"] += 1

                if reachable:
                    results["up"] += 1
                    vm.consecutive_fails = 0
                    vm.is_reachable = True
                    # Award uptime points to blue team
                    blue_team.defense_points += POINTS["service_up_per_check"]
                    blue_team.score          += POINTS["service_up_per_check"]
                else:
                    results["down"] += 1
                    vm.consecutive_fails += 1
                    vm.is_reachable = False

                    # Penalise blue team
                    penalty = abs(POINTS["service_down_per_check"])
                    blue_team.penalty_points += penalty
                    blue_team.score          -= penalty

                    # Track downtime
                    if blue_team.last_downtime_start is None:
                        blue_team.last_downtime_start = datetime.now(timezone.utc)

                    results["downtime_penalties"].append(
                        f"{vm.display_name}:{service_name} DOWN"
                    )

                    self._event(game, "service_down",
                                f"{vm.display_name} {service_name} unreachable",
                                team_id=blue_team.id,
                                points=-penalty)

                vm.last_check_at = datetime.now(timezone.utc)

        # Update cumulative downtime
        if blue_team and blue_team.last_downtime_start:
            elapsed = (datetime.now(timezone.utc) - blue_team.last_downtime_start).total_seconds()
            blue_team.total_downtime_seconds += int(elapsed)
            blue_team.last_downtime_start = None

            # Check loss condition
            downtime_minutes = blue_team.total_downtime_seconds / 60
            if downtime_minutes >= game.max_downtime_minutes:
                self._event(game, "blue_lost_downtime",
                            f"Blue team exceeded {game.max_downtime_minutes}min downtime — Red wins!")
                game.status   = GameStatus.ended
                game.ended_at = datetime.now(timezone.utc)

        self.db.commit()
        return results

    # ═══════════════════════════════════════════════════════
    # MILESTONE SCORING (called from routes when Red achieves something)
    # ═══════════════════════════════════════════════════════
    def award_milestone(self, game: Game, team: Team, milestone: str,
                        user_id: int = None) -> int:
        points = POINTS.get(milestone, 0)
        if points > 0:
            team.attack_points += points
            team.score         += points
            self._event(game, f"milestone_{milestone}",
                        f"Milestone achieved: {milestone} (+{points} pts)",
                        team_id=team.id, points=points, user_id=user_id)
            self.db.commit()
        return points

    # ═══════════════════════════════════════════════════════
    # ANSIBLE
    # ═══════════════════════════════════════════════════════
    async def _run_ansible(self, game: Game, vm_records: list,
                           selected_vulns: list) -> None:
        inventory_path = f"/tmp/coco-inv-{game.id}.ini"
        vuln_vars_path = f"/tmp/coco-vulns-{game.id}.json"

        # Build inventory
        lines = ["[all]\n"]
        for (vm, _, _, _, ip) in vm_records:
            if vm.status != VMStatus.running:
                continue
            if vm.role == "attacker":
                # The Kali box is the Red Team's tool — never configured by us.
                continue
            win = is_windows(vm.vm_type)
            user = "Administrator" if win else "root"
            conn = "winrm" if win else "ssh"
            extra = (" ansible_password=Coco2024! ansible_winrm_transport=basic "
                     "ansible_winrm_server_cert_validation=ignore ansible_port=5985"
                     if win else " ansible_password=coco2024")
            lines.append(
                f"{vm.name} ansible_host={ip} ansible_user={user} "
                f"ansible_connection={conn}{extra} vm_role={vm.role}\n"
            )

        role_groups = {}
        for (vm, *_) in vm_records:
            if vm.role == "attacker":
                continue
            role_groups.setdefault(vm.role, []).append(vm.name)
        for role, members in role_groups.items():
            lines.append(f"\n[{role}]\n")
            lines.extend(f"{m}\n" for m in members)

        with open(inventory_path, "w") as f:
            f.writelines(lines)

        # Build vuln vars
        vuln_vars = {
            "coco_game_id":      game.id,
            "coco_mode":         game.mode,
            "coco_active_vulns": selected_vulns,
            "coco_flags":        game.flags_config,
        }
        with open(vuln_vars_path, "w") as f:
            json.dump(vuln_vars, f)

        # Choose the playbook: fully-Linux sessions use the collection-free
        # deploy-linux.yml (works even without the Windows Galaxy collections);
        # anything with a Windows VM uses the full deploy-session.yml.
        has_windows = any(
            is_windows(vm.vm_type)
            for (vm, *_ ) in vm_records
            if vm.status == VMStatus.running
        )
        playbook_name = "deploy-session.yml" if has_windows else "deploy-linux.yml"
        playbook = os.path.join(
            settings.coco_repo_dir,
            "ansible", playbook_name
        )
        if not os.path.exists(playbook):
            self._event(game, "ansible_skip",
                        f"Playbook not found: {playbook} — skipping Ansible")
            return
        self._event(game, "ansible_playbook", f"Using {playbook_name}")

        cmd = [
            "ansible-playbook", playbook,
            "-i", inventory_path,
            "--extra-vars", f"@{vuln_vars_path}",
            "--timeout", "60",
            "-v",
        ]

        ansible_dir = os.path.join(settings.coco_repo_dir, "ansible")
        env = dict(os.environ)
        env["ANSIBLE_HOST_KEY_CHECKING"] = "False"
        env["ANSIBLE_CONFIG"] = os.path.join(ansible_dir, "ansible.cfg")
        env["ANSIBLE_ROLES_PATH"] = os.path.join(ansible_dir, "roles")

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=ansible_dir,
                env=env,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=600)
            if proc.returncode != 0:
                self._event(game, "ansible_warn",
                            f"Ansible exit {proc.returncode}: {stderr.decode()[:300]}")
            else:
                self._event(game, "ansible_ok", "Ansible completed successfully")
        except asyncio.TimeoutError:
            self._event(game, "ansible_warn", "Ansible timed out after 10min")
        except Exception as e:
            self._event(game, "ansible_warn", f"Ansible error: {e}")
        finally:
            for f in (inventory_path, vuln_vars_path):
                try:
                    os.remove(f)
                except Exception:
                    pass

    # ═══════════════════════════════════════════════════════
    # GUACAMOLE
    # ═══════════════════════════════════════════════════════
    def _register_guacamole(self, vm: VM, ip: str) -> str:
        import xml.etree.ElementTree as ET

        xml_path = "/etc/guacamole/user-mapping.xml"
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
        except Exception:
            return ""

        protocol = "rdp" if is_windows(vm.vm_type) else "ssh"
        conn_id  = f"game{vm.game_id}-{vm.name}"

        username, password = DEFAULT_CREDS[protocol]

        for auth in root.findall("authorize"):
            existing = [c.get("name") for c in auth.findall("connection")]
            if conn_id in existing:
                continue

            conn  = ET.SubElement(auth, "connection")
            conn.set("name", conn_id)
            ET.SubElement(conn, "protocol").text = protocol

            params = {
                "hostname":    ip,
                "port":        "3389" if protocol == "rdp" else "22",
                "username":    username,
                "password":    password,
                "ignore-cert": "true",
            }
            if protocol == "rdp":
                params["security"] = "any"
                params["resize-method"] = "reconnect"

            for k, v in params.items():
                p = ET.SubElement(conn, "param")
                p.set("name", k)
                p.text = v

        ET.indent(root)
        tree.write(xml_path, encoding="unicode", xml_declaration=False)
        return conn_id

    def _cleanup_guacamole(self, game_id: int) -> None:
        import xml.etree.ElementTree as ET
        xml_path = "/etc/guacamole/user-mapping.xml"
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
            prefix = f"game{game_id}-"
            for auth in root.findall("authorize"):
                for conn in auth.findall("connection"):
                    if conn.get("name", "").startswith(prefix):
                        auth.remove(conn)
            ET.indent(root)
            tree.write(xml_path, encoding="unicode", xml_declaration=False)
        except Exception:
            pass

    # ═══════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════
    def _select_vulns(self, difficulty) -> list:
        # difficulty is a VulnDifficulty enum (str subclass). Use its value so
        # "easy"/"medium"/"hard" resolve correctly (str(enum) would give
        # "VulnDifficulty.medium" on some Python versions).
        key = getattr(difficulty, "value", str(difficulty))
        count = VULNS_PER_CATEGORY.get(key, 2)
        selected = []
        for category, vulns in VULN_POOL.items():
            selected.extend(random.sample(vulns, min(count, len(vulns))))
        return selected

    def _vuln_applies_to_role(self, vuln: str, role: str) -> bool:
        ad_common = ["ad_kerberoastable_svc", "ad_asrep_roasting",
                     "ad_password_spray", "smb_signing_disabled",
                     "smb_anonymous_read", "ad_krbtgt_old",
                     "win_weak_gpo", "win_unquoted_service",
                     "scheduled_task_writable", "registry_autorun"]
        mapping = {
            "web":          ["webserver_sqli", "webserver_rce_upload", "webserver_lfi"],
            "dc-primary":   ad_common,
            "dc-secondary": ad_common,
            "dc-mssql":     ["mssql_xp_cmdshell", "mssql_sa_weak_password",
                             "win_unquoted_service"],
            "fileserver":   ["smb_anonymous_read", "smb_signing_disabled",
                             "win_unquoted_service"],
            "linux":        ["linux_suid_bash", "linux_sudo_nopasswd",
                             "smb_anonymous_read"],
            "workstation":  ["win_unquoted_service", "registry_autorun"],
        }
        return vuln in mapping.get(role, [])

    def _build_flags_config(self, mode: GameMode) -> list:
        # One flag per "flag-worthy" blue VM in the mode. The `service` value
        # is the VM `name` so Ansible's place_flags.yml knows where to drop it.
        # Points scale with how deep into the network the VM is.
        points_by_role = {
            "web":          100,
            "linux":        200,
            "fileserver":   300,
            "dc-mssql":     400,
            "dc-primary":   500,
            "dc-secondary": 500,
        }
        flags = []
        seen = set()
        for vm_def in GAME_VMS.get(mode, []):
            if vm_def["team"] != "blue":
                continue
            role = vm_def["role"]
            if role not in points_by_role:
                continue          # workstation / siem don't hold flags
            if vm_def["name"] in seen:
                continue
            seen.add(vm_def["name"])
            flags.append({
                "service":     vm_def["name"],
                "display":     vm_def["display"],
                "flag_value":  f"COCO{{{secrets.token_hex(12)}}}",
                "points":      points_by_role[role],
                "captured":    False,
                "captured_by": None,
            })
        return flags

    async def _check_service(self, ip: str, port: int,
                              timeout: float = 3.0) -> tuple:
        if not ip:
            return False, None
        start = asyncio.get_event_loop().time()
        try:
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(ip, port), timeout=timeout
            )
            writer.close()
            latency = (asyncio.get_event_loop().time() - start) * 1000
            return True, round(latency, 1)
        except Exception:
            return False, None

    def _event(self, game: Game, event_type: str, detail: str,
               team_id: int = None, points: int = 0,
               user_id: int = None) -> None:
        ev = GameEvent(
            game_id    = game.id,
            user_id    = user_id,
            team_id    = team_id,
            event_type = event_type,
            detail     = detail,
            points     = points,
        )
        self.db.add(ev)
        self.db.commit()
