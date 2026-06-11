from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from core.database import get_db
from core.security import require_admin
from models.user import User
from models.game import Game, AuditLog

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users")
def list_users(db: Session = Depends(get_db), _=Depends(require_admin)):
    users = db.query(User).order_by(User.created_at.desc()).all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "email": u.email,
            "role": u.role,
            "team_type": u.team_type,
            "is_active": u.is_active,
            "last_login": u.last_login,
            "created_at": u.created_at,
        }
        for u in users
    ]


@router.patch("/users/{user_id}/toggle")
def toggle_user(user_id: int, db: Session = Depends(get_db), _=Depends(require_admin)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = not user.is_active
    db.commit()
    return {"user_id": user_id, "is_active": user.is_active}


@router.get("/stats")
def system_stats(db: Session = Depends(get_db), _=Depends(require_admin)):
    return {
        "total_users": db.query(User).count(),
        "active_users": db.query(User).filter(User.is_active == True).count(),
        "total_games": db.query(Game).count(),
        "running_games": db.query(Game).filter(Game.status == "running").count(),
        "flags_captured": db.query(Game).filter(Game.flag_captured == True).count(),
    }


@router.get("/audit")
def audit_logs(
    limit: int = 100,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    logs = db.query(AuditLog).order_by(AuditLog.timestamp.desc()).limit(limit).all()
    return [
        {
            "id": l.id,
            "user_id": l.user_id,
            "action": l.action,
            "resource": l.resource,
            "ip_address": l.ip_address,
            "timestamp": l.timestamp,
        }
        for l in logs
    ]
