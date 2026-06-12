import httpx
from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import StreamingResponse, Response
from core.security import get_current_user
from core.config import get_settings

settings = get_settings()
router = APIRouter(tags=["guacamole"])

GUAC_BASE = "http://localhost:8080"


async def _proxy(request: Request, path: str) -> Response:
    url = f"{GUAC_BASE}/{path}"
    async with httpx.AsyncClient(timeout=30) as client:
        try:
            resp = await client.request(
                method=request.method,
                url=url,
                headers={k: v for k, v in request.headers.items()
                         if k.lower() not in ("host", "content-length")},
                content=await request.body(),
                follow_redirects=True,
            )
            return Response(
                content=resp.content,
                status_code=resp.status_code,
                headers=dict(resp.headers),
                media_type=resp.headers.get("content-type"),
            )
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Guacamole service unavailable")


@router.api_route(
    "/guacamole/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"],
)
async def guacamole_proxy(
    path: str,
    request: Request,
    current_user=Depends(get_current_user),
):
    return await _proxy(request, f"guacamole/{path}")


@router.get("/api/terminal/connections")
async def list_connections(current_user=Depends(get_current_user)):
    from core.database import SessionLocal
    from models.game import VM
    db = SessionLocal()
    try:
        if current_user.team_id:
            vms = db.query(VM).filter(
                VM.status == "running"
            ).all()
        else:
            vms = []
        return [
            {
                "id": vm.id,
                "name": vm.name,
                "type": vm.vm_type,
                "team": vm.team_type,
                "ip": vm.ip_address,
                "protocol": "rdp" if "win" in vm.vm_type else "ssh",
            }
            for vm in vms
        ]
    finally:
        db.close()
