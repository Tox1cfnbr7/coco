"""
COCO — Proxmox API Service
Handles all VM operations: clone, start, stop, delete, status
"""

import httpx
import asyncio
from typing import Optional
from core.config import get_settings

settings = get_settings()


class ProxmoxAPI:
    """
    Thin async wrapper around the Proxmox VE REST API.
    All calls go to https://<host>:8006/api2/json/
    """

    def __init__(self):
        self.base    = f"https://{settings.proxmox_host}:8006/api2/json"
        self.node    = settings.proxmox_node
        self._ticket = None
        self._csrf   = None
        self._client = httpx.AsyncClient(verify=False, timeout=30)

    # ── Auth ──────────────────────────────────────────────────
    async def _login(self) -> None:
        resp = await self._client.post(
            f"{self.base}/access/ticket",
            data={
                "username": settings.proxmox_user,
                "password": settings.proxmox_password,
            },
        )
        resp.raise_for_status()
        data = resp.json()["data"]
        self._ticket = data["ticket"]
        self._csrf   = data["CSRFPreventionToken"]

    async def _headers(self) -> dict:
        if not self._ticket:
            await self._login()
        return {
            "CSRFPreventionToken": self._csrf,
            "Cookie": f"PVEAuthCookie={self._ticket}",
        }

    async def _get(self, path: str) -> dict:
        r = await self._client.get(
            f"{self.base}/{path}",
            headers=await self._headers(),
        )
        if r.status_code == 401:
            self._ticket = None
            await self._login()
            r = await self._client.get(
                f"{self.base}/{path}",
                headers=await self._headers(),
            )
        r.raise_for_status()
        return r.json().get("data", {})

    async def _post(self, path: str, data: dict = None) -> dict:
        r = await self._client.post(
            f"{self.base}/{path}",
            headers=await self._headers(),
            json=data or {},
        )
        if r.status_code == 401:
            self._ticket = None
            await self._login()
            r = await self._client.post(
                f"{self.base}/{path}",
                headers=await self._headers(),
                json=data or {},
            )
        r.raise_for_status()
        return r.json().get("data", {})

    async def _delete(self, path: str) -> dict:
        r = await self._client.delete(
            f"{self.base}/{path}",
            headers=await self._headers(),
        )
        r.raise_for_status()
        return r.json().get("data", {})

    # ── Node info ─────────────────────────────────────────────
    async def node_status(self) -> dict:
        return await self._get(f"nodes/{self.node}/status")

    async def list_vms(self) -> list:
        return await self._get(f"nodes/{self.node}/qemu")

    async def next_vmid(self) -> int:
        data = await self._get("cluster/nextid")
        return int(data)

    # ── VM lifecycle ──────────────────────────────────────────
    async def clone_vm(
        self,
        template_id: int,
        new_id: int,
        name: str,
        full: bool = True,
    ) -> str:
        """Clone a template VM. Returns task UPID."""
        task = await self._post(
            f"nodes/{self.node}/qemu/{template_id}/clone",
            {
                "newid":    new_id,
                "name":     name,
                "full":     1 if full else 0,
                "target":   self.node,
            },
        )
        return task  # UPID string

    async def start_vm(self, vmid: int) -> str:
        return await self._post(f"nodes/{self.node}/qemu/{vmid}/status/start")

    async def stop_vm(self, vmid: int) -> str:
        return await self._post(f"nodes/{self.node}/qemu/{vmid}/status/stop")

    async def shutdown_vm(self, vmid: int) -> str:
        return await self._post(f"nodes/{self.node}/qemu/{vmid}/status/shutdown")

    async def delete_vm(self, vmid: int) -> str:
        return await self._delete(f"nodes/{self.node}/qemu/{vmid}")

    async def vm_status(self, vmid: int) -> dict:
        return await self._get(f"nodes/{self.node}/qemu/{vmid}/status/current")

    async def vm_config(self, vmid: int) -> dict:
        return await self._get(f"nodes/{self.node}/qemu/{vmid}/config")

    async def set_vm_config(self, vmid: int, config: dict) -> dict:
        r = await self._client.put(
            f"{self.base}/nodes/{self.node}/qemu/{vmid}/config",
            headers=await self._headers(),
            json=config,
        )
        r.raise_for_status()
        return r.json().get("data", {})

    # ── Networking ────────────────────────────────────────────
    async def create_vlan(self, vlan_id: int, bridge: str = "vmbr1") -> None:
        """Create a VLAN-aware bridge interface on Proxmox node."""
        await self._post(
            f"nodes/{self.node}/network",
            {
                "iface":    f"vmbr{vlan_id}",
                "type":     "bridge",
                "bridge_vids": str(vlan_id),
                "comments": f"COCO Game VLAN {vlan_id}",
            },
        )

    async def apply_network(self) -> None:
        await self._post(f"nodes/{self.node}/network")

    # ── Task tracking ─────────────────────────────────────────
    async def wait_for_task(self, upid: str, timeout: int = 120) -> bool:
        """Poll a task until it finishes. Returns True on success."""
        node = upid.split(":")[1] if ":" in upid else self.node
        elapsed = 0
        while elapsed < timeout:
            status = await self._get(f"nodes/{node}/tasks/{upid}/status")
            if status.get("status") == "stopped":
                return status.get("exitstatus") == "OK"
            await asyncio.sleep(3)
            elapsed += 3
        return False


# ── Singleton ─────────────────────────────────────────────
_proxmox: Optional[ProxmoxAPI] = None


def get_proxmox() -> ProxmoxAPI:
    global _proxmox
    if _proxmox is None:
        _proxmox = ProxmoxAPI()
    return _proxmox
