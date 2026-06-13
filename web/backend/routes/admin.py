"""
COCO — Admin API v2
Proxmox live stats, template management, VM control, system health.
"""

import asyncio
import os
import subprocess
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from core.database import get_db
from core.security import require_admin, get_current_user
from models.user import User
from models.game import Game, VM, GameStatus, VMStatus, CapturedFlag
from services.proxmox import get_proxmox

router = APIRouter(prefix="/admin", tags=["admin"])

# ── Proxmox Node Stats ─────────────────────────────────────

@router.get("/proxmox/status")
async def proxmox_status(_=Depends(require_admin)):
    """Live Proxmox node CPU/RAM/disk/network stats."""
    try:
        pve = get_proxmox()
        status = await pve.node_status()
        vms    = await pve.list_vms()

        return {
            "node":       os.getenv("PROXMOX_NODE", "coco"),
            "cpu_pct":    round(status.get("cpu", 0) * 100, 1),
            "ram_used_gb": round(status.get("memory", {}).get("used", 0) / 1073741824, 1),
            "ram_total_gb": round(status.get("memory", {}).get("total", 0) / 1073741824, 1),
            "ram_pct":    round(
                status.get("memory", {}).get("used", 0) /
                max(status.get("memory", {}).get("total", 1), 1) * 100, 1
            ),
            "disk_used_gb": round(status.get("rootfs", {}).get("used", 0) / 1073741824, 1),
            "disk_total_gb": round(status.get("rootfs", {}).get("total", 0) / 1073741824, 1),
            "uptime_hours": round(status.get("uptime", 0) / 3600, 1),
            "vm_count":   len(vms),
            "vm_running": sum(1 for v in vms if v.get("status") == "running"),
            "pve_version": status.get("pveversion", "unknown"),
        }
    except Exception as e:
        raise HTTPException(503, f"Proxmox unreachable: {e}")


@router.get("/proxmox/storage")
async def proxmox_storage(_=Depends(require_admin)):
    """Storage pool usage."""
    try:
        pve  = get_proxmox()
        data = await pve._get(f"nodes/{os.getenv('PROXMOX_NODE','coco')}/storage")
        return [
            {
                "storage": s.get("storage"),
                "type":    s.get("type"),
                "used_gb": round(s.get("used", 0) / 1073741824, 1),
                "total_gb": round(s.get("total", 0) / 1073741824, 1),
                "pct":     round(s.get("used_fraction", 0) * 100, 1),
                "active":  s.get("active", False),
            }
            for s in data
            if s.get("active")
        ]
    except Exception as e:
        raise HTTPException(503, str(e))


@router.get("/proxmox/vms")
async def list_all_vms(_=Depends(require_admin)):
    """All VMs on Proxmox node with status."""
    try:
        pve  = get_proxmox()
        vms  = await pve.list_vms()
        return sorted(
            [
                {
                    "vmid":   v.get("vmid"),
                    "name":   v.get("name", ""),
                    "status": v.get("status"),
                    "cpu":    round(v.get("cpu", 0) * 100, 1),
                    "ram_mb": round(v.get("mem", 0) / 1048576, 0),
                    "is_template": v.get("template", 0) == 1,
                    "is_coco": v.get("name", "").startswith("coco-"),
                }
                for v in vms
            ],
            key=lambda x: (not x["is_coco"], x["vmid"])
        )
    except Exception as e:
        raise HTTPException(503, str(e))


# ── VM Control ─────────────────────────────────────────────

@router.post("/proxmox/vms/{vmid}/start")
async def vm_start(vmid: int, _=Depends(require_admin)):
    pve = get_proxmox()
    await pve.start_vm(vmid)
    return {"vmid": vmid, "action": "start", "ok": True}


@router.post("/proxmox/vms/{vmid}/stop")
async def vm_stop(vmid: int, _=Depends(require_admin)):
    pve = get_proxmox()
    await pve.stop_vm(vmid)
    return {"vmid": vmid, "action": "stop", "ok": True}


@router.post("/proxmox/vms/{vmid}/restart")
async def vm_restart(vmid: int, _=Depends(require_admin)):
    pve = get_proxmox()
    await pve.stop_vm(vmid)
    await asyncio.sleep(5)
    await pve.start_vm(vmid)
    return {"vmid": vmid, "action": "restart", "ok": True}


@router.delete("/proxmox/vms/{vmid}")
async def vm_delete(vmid: int, _=Depends(require_admin)):
    pve = get_proxmox()
    try:
        await pve.stop_vm(vmid)
        await asyncio.sleep(3)
    except Exception:
        pass
    await pve.delete_vm(vmid)
    return {"vmid": vmid, "action": "delete", "ok": True}


# ── Template Management ────────────────────────────────────

@router.get("/templates")
async def list_templates(_=Depends(require_admin)):
    """List all Packer templates (built + available to build)."""
    try:
        pve = get_proxmox()
        vms = await pve.list_vms()
        built = {
            v["name"]: {
                "vmid":   v["vmid"],
                "name":   v["name"],
                "status": "built",
                "built":  True,
            }
            for v in vms
            if v.get("template", 0) == 1 and v.get("name", "").startswith("coco-tpl-")
        }
    except Exception:
        built = {}

    # All available templates (from repo)
    repo_dir = os.getenv("COCO_REPO_DIR", "/opt/coco/repo")
    tpl_dir  = os.path.join(repo_dir, "templates")
    available = []

    TEMPLATE_META = {
        "kali":      {"label": "Kali Linux 2024", "role": "attacker", "ram_gb": 8,  "disk_gb": 80},
        "debian12":  {"label": "Debian 12",        "role": "web/linux","ram_gb": 2,  "disk_gb": 40},
        "win2022":   {"label": "Windows Server 2022","role": "dc/mssql","ram_gb": 8,  "disk_gb": 80},
        "win10":     {"label": "Windows 10",        "role": "workstation","ram_gb": 4,"disk_gb": 60},
        "dc02-ca":   {"label": "Win Server 2022 CA","role": "dc-ca",   "ram_gb": 4,  "disk_gb": 60},
        "siem":      {"label": "SIEM (Elastic+Wazuh)","role": "siem",  "ram_gb": 16, "disk_gb": 100},
    }

    for tpl_name, meta in TEMPLATE_META.items():
        vm_name = f"coco-tpl-{tpl_name}"
        if vm_name in built:
            entry = {**built[vm_name], **meta, "template_key": tpl_name}
        else:
            entry = {
                "vmid":   None,
                "name":   vm_name,
                "status": "not_built",
                "built":  False,
                "template_key": tpl_name,
                **meta,
            }

        # Check if build is currently running
        log_file = f"/var/log/coco/packer-{tpl_name}.log"
        pid_file = f"/var/run/coco-packer-{tpl_name}.pid"
        if os.path.exists(pid_file):
            try:
                pid = int(open(pid_file).read().strip())
                os.kill(pid, 0)
                entry["status"] = "building"
            except (ProcessLookupError, ValueError):
                os.remove(pid_file)

        available.append(entry)

    return available


@router.post("/templates/{template_key}/build")
async def build_template(template_key: str, _=Depends(require_admin)):
    """Start a Packer build in the background."""
    pid_file = f"/var/run/coco-packer-{template_key}.pid"
    if os.path.exists(pid_file):
        try:
            pid = int(open(pid_file).read().strip())
            os.kill(pid, 0)
            raise HTTPException(400, f"Template '{template_key}' is already building (PID {pid})")
        except ProcessLookupError:
            os.remove(pid_file)

    repo_dir = os.getenv("COCO_REPO_DIR", "/opt/coco/repo")
    script   = os.path.join(repo_dir, "templates", "build-templates.sh")

    if not os.path.exists(script):
        raise HTTPException(404, "build-templates.sh not found in templates/")

    log_file = f"/var/log/coco/packer-{template_key}.log"
    os.makedirs("/var/log/coco", exist_ok=True)

    proc = subprocess.Popen(
        ["bash", script, "--template", template_key],
        stdout=open(log_file, "w"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    with open(pid_file, "w") as f:
        f.write(str(proc.pid))

    return {
        "template":  template_key,
        "pid":       proc.pid,
        "log_file":  log_file,
        "message":   f"Build started. Stream logs at /api/admin/templates/{template_key}/logs",
    }


@router.delete("/templates/{vmid}")
async def delete_template(vmid: int, _=Depends(require_admin)):
    pve = get_proxmox()
    await pve.delete_vm(vmid)
    return {"vmid": vmid, "deleted": True}


@router.get("/templates/{template_key}/logs")
def template_build_logs(template_key: str, _=Depends(require_admin)):
    """Stream Packer build log as plain text."""
    log_file = f"/var/log/coco/packer-{template_key}.log"
    if not os.path.exists(log_file):
        raise HTTPException(404, "No log file found — has the build started?")

    def generate():
        with open(log_file, "r") as f:
            while True:
                line = f.readline()
                if line:
                    yield line
                else:
                    # Check if build is still running
                    pid_file = f"/var/run/coco-packer-{template_key}.pid"
                    if not os.path.exists(pid_file):
                        break
                    import time; time.sleep(0.5)

    return StreamingResponse(generate(), media_type="text/plain")


# ── WebSocket: live log stream ─────────────────────────────

@router.websocket("/ws/logs/{template_key}")
async def ws_build_logs(websocket: WebSocket, template_key: str):
    """WebSocket that streams Packer build log lines in real-time."""
    await websocket.accept()
    log_file = f"/var/log/coco/packer-{template_key}.log"
    pid_file = f"/var/run/coco-packer-{template_key}.pid"

    try:
        sent = 0
        while True:
            if os.path.exists(log_file):
                with open(log_file, "r") as f:
                    lines = f.readlines()
                for line in lines[sent:]:
                    await websocket.send_text(line.rstrip())
                    sent = len(lines)

            # Stop when PID file gone (build finished)
            still_running = False
            if os.path.exists(pid_file):
                try:
                    pid = int(open(pid_file).read().strip())
                    os.kill(pid, 0)
                    still_running = True
                except (ProcessLookupError, ValueError):
                    os.remove(pid_file)

            if not still_running and sent >= len(
                open(log_file).readlines() if os.path.exists(log_file) else []
            ):
                await websocket.send_text("__BUILD_DONE__")
                break

            await asyncio.sleep(0.5)

    except WebSocketDisconnect:
        pass


# ── WebSocket: Proxmox stats stream ───────────────────────

@router.websocket("/ws/stats")
async def ws_proxmox_stats(websocket: WebSocket):
    """Push Proxmox node stats every 5 seconds."""
    import json
    await websocket.accept()
    try:
        while True:
            try:
                pve    = get_proxmox()
                status = await pve.node_status()
                vms    = await pve.list_vms()
                data = {
                    "cpu_pct":    round(status.get("cpu", 0) * 100, 1),
                    "ram_pct":    round(
                        status.get("memory", {}).get("used", 0) /
                        max(status.get("memory", {}).get("total", 1), 1) * 100, 1
                    ),
                    "ram_used_gb": round(status.get("memory", {}).get("used", 0) / 1073741824, 1),
                    "ram_total_gb": round(status.get("memory", {}).get("total", 0) / 1073741824, 1),
                    "vm_running": sum(1 for v in vms if v.get("status") == "running"),
                    "vm_count":   len(vms),
                    "ts":         datetime.now(timezone.utc).isoformat(),
                }
                await websocket.send_text(json.dumps(data))
            except Exception as e:
                await websocket.send_text(json.dumps({"error": str(e)}))
            await asyncio.sleep(5)
    except WebSocketDisconnect:
        pass


# ── Session Management ─────────────────────────────────────

@router.get("/sessions")
def admin_sessions(db: Session = Depends(get_db), _=Depends(require_admin)):
    games = db.query(Game).order_by(Game.created_at.desc()).limit(100).all()
    return [
        {
            "id":       g.id,
            "name":     g.name,
            "mode":     g.mode,
            "status":   g.status,
            "vm_count": len(g.vms),
            "started_at": g.started_at,
            "ended_at":   g.ended_at,
        }
        for g in games
    ]


# ── System health ──────────────────────────────────────────

@router.get("/health")
def system_health(db: Session = Depends(get_db), _=Depends(require_admin)):
    import redis as redis_lib

    checks = {}

    # DB
    try:
        db.execute(__import__("sqlalchemy").text("SELECT 1"))
        checks["database"] = {"ok": True}
    except Exception as e:
        checks["database"] = {"ok": False, "error": str(e)}

    # Redis
    try:
        r = redis_lib.from_url(os.getenv("REDIS_URL", "redis://localhost:6379"))
        r.ping()
        checks["redis"] = {"ok": True}
    except Exception as e:
        checks["redis"] = {"ok": False, "error": str(e)}

    # Guacamole
    import httpx
    try:
        resp = httpx.get("http://localhost:8080/guacamole/", timeout=3)
        checks["guacamole"] = {"ok": resp.status_code < 500}
    except Exception as e:
        checks["guacamole"] = {"ok": False, "error": str(e)}

    # Proxmox
    try:
        pve_url = os.getenv("PROXMOX_HOST", "127.0.0.1")
        resp    = httpx.get(f"https://{pve_url}:8006", verify=False, timeout=3)
        checks["proxmox"] = {"ok": True}
    except Exception as e:
        checks["proxmox"] = {"ok": False, "error": str(e)}

    # COCO service itself
    checks["coco"] = {"ok": True, "version": os.getenv("COCO_APP_VERSION", "?")}

    return {
        "all_ok": all(v["ok"] for v in checks.values()),
        "checks": checks,
        "ts":     datetime.now(timezone.utc).isoformat(),
    }


# ── Existing user/stats/audit endpoints ───────────────────

from models.game import AuditLog

@router.get("/users")
def list_users(db: Session = Depends(get_db), _=Depends(require_admin)):
    users = db.query(User).order_by(User.created_at.desc()).all()
    return [
        {
            "id": u.id, "username": u.username, "email": u.email,
            "role": u.role, "team_type": u.team_type,
            "is_active": u.is_active, "last_login": u.last_login,
            "created_at": u.created_at,
        }
        for u in users
    ]


@router.patch("/users/{user_id}/toggle")
def toggle_user(user_id: int, db: Session = Depends(get_db), _=Depends(require_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    user.is_active = not user.is_active
    db.commit()
    return {"user_id": user_id, "is_active": user.is_active}


@router.get("/stats")
def system_stats(db: Session = Depends(get_db), _=Depends(require_admin)):
    return {
        "total_users":    db.query(User).count(),
        "active_users":   db.query(User).filter(User.is_active == True).count(),
        "total_games":    db.query(Game).count(),
        "running_games":  db.query(Game).filter(Game.status == "running").count(),
        "flags_captured": db.query(CapturedFlag).count(),
    }


@router.get("/audit")
def audit_logs(limit: int = 100, db: Session = Depends(get_db), _=Depends(require_admin)):
    logs = db.query(AuditLog).order_by(AuditLog.timestamp.desc()).limit(limit).all()
    return [
        {"id": l.id, "user_id": l.user_id, "action": l.action,
         "resource": l.resource, "ip_address": l.ip_address, "timestamp": l.timestamp}
        for l in logs
    ]
