"""
COCO — Sessions API
Manages game sessions: create, start, kill, status, scoreboard.
"""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
import secrets
import string

from core.database import get_db
from core.security import get_current_user, require_admin
from models.user import User
from models.game import (
    Game, Team, VM, GameEvent, ServiceCheck, CapturedFlag,
    GameStatus, GameMode, GameDuration, VulnDifficulty
)

router = APIRouter(prefix="/sessions", tags=["sessions"])


def _join_code(n: int = 8) -> str:
    return "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(n))


# ── Request models ─────────────────────────────────────────

class CreateSessionRequest(BaseModel):
    name:                str
    mode:                GameMode
    duration:            GameDuration
    vuln_difficulty:     VulnDifficulty = VulnDifficulty.medium
    max_downtime_minutes: int           = 30


class FlagSubmitRequest(BaseModel):
    flag: str


class MilestoneRequest(BaseModel):
    milestone: str   # initial_access | lateral_movement | domain_admin | data_exfil | persistence


# ── Endpoints ──────────────────────────────────────────────

@router.get("/")
def list_sessions(
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    games = db.query(Game).order_by(Game.created_at.desc()).limit(50).all()
    return [_game_summary(g) for g in games]


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_session(
    req:          CreateSessionRequest,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(require_admin),
):
    game = Game(
        name                 = req.name,
        mode                 = req.mode,
        duration             = req.duration,
        vuln_difficulty      = req.vuln_difficulty,
        max_downtime_minutes = req.max_downtime_minutes,
        flags_config         = [],
        created_by           = current_user.id,
    )
    db.add(game)
    db.flush()

    red_team  = Team(game_id=game.id, type="red",  join_code=_join_code())
    blue_team = Team(game_id=game.id, type="blue", join_code=_join_code())
    db.add_all([red_team, blue_team])
    db.commit()
    db.refresh(game)

    return {
        "id":              game.id,
        "name":            game.name,
        "mode":            game.mode,
        "status":          game.status,
        "red_join_code":   red_team.join_code,
        "blue_join_code":  blue_team.join_code,
    }


@router.get("/{game_id}")
def get_session(
    game_id:      int,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    game = _get_or_404(db, game_id)
    return _game_detail(game, current_user)


@router.post("/{game_id}/start")
async def start_session(
    game_id:          int,
    background_tasks: BackgroundTasks,
    db:               Session = Depends(get_db),
    current_user:     User    = Depends(require_admin),
):
    game = _get_or_404(db, game_id)
    if game.status != GameStatus.waiting:
        raise HTTPException(400, "Session is not in waiting state")

    background_tasks.add_task(_provision_session, game.id)
    return {"message": "Session provisioning started", "session_id": game_id}


@router.post("/{game_id}/kill")
async def kill_session(
    game_id:          int,
    background_tasks: BackgroundTasks,
    db:               Session = Depends(get_db),
    current_user:     User    = Depends(require_admin),
):
    game = _get_or_404(db, game_id)
    if game.status not in (GameStatus.running, GameStatus.provisioning, GameStatus.error):
        raise HTTPException(400, "Session is not active")

    background_tasks.add_task(_kill_session, game.id, "admin_kill")
    return {"message": "Session kill initiated", "session_id": game_id}


@router.post("/{game_id}/join")
def join_session(
    game_id:      int,
    join_code:    str,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    team = db.query(Team).filter(
        Team.game_id  == game_id,
        Team.join_code == join_code.upper()
    ).first()
    if not team:
        raise HTTPException(404, "Invalid join code")

    current_user.team_id   = team.id
    current_user.team_type = team.type
    db.commit()
    return {"message": f"Joined {team.type} team", "team_id": team.id}


@router.post("/{game_id}/flag")
def submit_flag(
    game_id:      int,
    req:          FlagSubmitRequest,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    game = _get_or_404(db, game_id)
    if game.status != GameStatus.running:
        raise HTTPException(400, "Session is not running")
    if current_user.team_type != "red":
        raise HTTPException(403, "Only Red Team can submit flags")

    flags = game.flags_config or []
    for flag in flags:
        if flag.get("captured"):
            continue
        if req.flag.strip() == flag.get("flag_value", ""):
            flag["captured"]    = True
            flag["captured_by"] = current_user.username
            flag["captured_at"] = datetime.now(timezone.utc).isoformat()

            # Update score
            red_team = db.query(Team).filter(
                Team.game_id == game_id, Team.type == "red"
            ).first()
            if red_team:
                pts = flag.get("points", 100)
                red_team.attack_points += pts
                red_team.score         += pts

                db.add(CapturedFlag(
                    game_id     = game_id,
                    team_id     = red_team.id,
                    captured_by = current_user.id,
                    service     = flag.get("service", "unknown"),
                    flag_value  = req.flag.strip(),
                    points      = pts,
                ))
                db.add(GameEvent(
                    game_id    = game_id,
                    user_id    = current_user.id,
                    team_id    = red_team.id,
                    event_type = "flag_captured",
                    detail     = f"Flag captured: {flag['service']} (+{pts} pts)",
                    points     = pts,
                ))

            # Check if all flags captured
            if all(f.get("captured") for f in flags):
                game.status   = GameStatus.ended
                game.ended_at = datetime.now(timezone.utc)
                db.add(GameEvent(
                    game_id=game_id, event_type="red_wins",
                    detail="All flags captured — Red Team wins!"
                ))

            from sqlalchemy.orm.attributes import flag_modified
            flag_modified(game, "flags_config")
            db.commit()

            return {
                "captured": True,
                "service":  flag["service"],
                "points":   flag.get("points", 100),
                "message":  f"Flag captured! +{flag.get('points', 100)} points",
            }

    raise HTTPException(400, "Wrong flag")


@router.post("/{game_id}/milestone")
def report_milestone(
    game_id:      int,
    req:          MilestoneRequest,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    """Red Team reports achieving a milestone (honour system + manual verify)."""
    game = _get_or_404(db, game_id)
    if game.status != GameStatus.running:
        raise HTTPException(400, "Session is not running")
    if current_user.team_type != "red":
        raise HTTPException(403, "Only Red Team can report milestones")

    red_team = db.query(Team).filter(
        Team.game_id == game_id, Team.type == "red"
    ).first()
    if not red_team:
        raise HTTPException(404, "Red team not found")

    from services.session_manager import POINTS, SessionManager
    pts = POINTS.get(req.milestone, 0)
    if pts == 0:
        raise HTTPException(400, f"Unknown milestone: {req.milestone}")

    mgr = SessionManager(db)
    awarded = mgr.award_milestone(game, red_team, req.milestone, current_user.id)

    # Check win condition for full_compromise / ransomware
    if req.milestone == "domain_admin" and game.mode in (
        GameMode.full_compromise, GameMode.ransomware_sim
    ):
        game.status   = GameStatus.ended
        game.ended_at = datetime.now(timezone.utc)
        db.add(GameEvent(
            game_id=game_id, event_type="red_wins",
            detail="Domain Admin achieved — Red Team wins!"
        ))
        db.commit()

    return {"milestone": req.milestone, "points_awarded": awarded}


@router.get("/{game_id}/scoreboard")
def get_scoreboard(
    game_id:      int,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    game = _get_or_404(db, game_id)
    teams = []
    for team in game.teams:
        downtime_min = team.total_downtime_seconds // 60
        teams.append({
            "type":            team.type,
            "score":           max(0, team.score),
            "attack_points":   team.attack_points,
            "defense_points":  team.defense_points,
            "penalty_points":  team.penalty_points,
            "downtime_minutes": downtime_min,
            "downtime_limit":  game.max_downtime_minutes,
            "downtime_pct":    min(100, int(downtime_min / game.max_downtime_minutes * 100))
                               if game.max_downtime_minutes > 0 else 0,
            "members":         len(team.members),
        })

    flags = []
    for f in (game.flags_config or []):
        flags.append({
            "service":    f.get("service"),
            "points":     f.get("points"),
            "captured":   f.get("captured", False),
            "captured_by": f.get("captured_by") if current_user.role == "admin" else None,
        })

    recent_events = db.query(GameEvent).filter(
        GameEvent.game_id == game_id
    ).order_by(GameEvent.timestamp.desc()).limit(20).all()

    return {
        "game_id":  game_id,
        "status":   game.status,
        "mode":     game.mode,
        "teams":    teams,
        "flags":    flags,
        "events":   [
            {
                "type":   e.event_type,
                "detail": e.detail,
                "points": e.points,
                "ts":     e.timestamp,
            }
            for e in recent_events
        ],
    }


@router.get("/{game_id}/vms")
def get_session_vms(
    game_id:      int,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    game = _get_or_404(db, game_id)
    vms  = db.query(VM).filter(VM.game_id == game_id).all()

    return [
        {
            "id":           vm.id,
            "name":         vm.display_name or vm.name,
            "type":         vm.vm_type,
            "role":         vm.role,
            "team":         vm.team_type,
            "ip":           vm.ip_address,
            "status":       vm.status,
            "reachable":    vm.is_reachable,
            "guacamole_id": vm.guacamole_id,
            # Only show injected vulns to admins — Blue Team doesn't know
            "vulns": vm.injected_vulns if current_user.role == "admin" else [],
        }
        for vm in vms
    ]


@router.get("/{game_id}/events")
def get_session_events(
    game_id:      int,
    limit:        int     = 50,
    db:           Session = Depends(get_db),
    current_user: User    = Depends(get_current_user),
):
    events = db.query(GameEvent).filter(
        GameEvent.game_id == game_id
    ).order_by(GameEvent.timestamp.desc()).limit(limit).all()

    return [
        {
            "type":   e.event_type,
            "detail": e.detail,
            "points": e.points,
            "ts":     e.timestamp,
        }
        for e in events
    ]


# ── Background task functions ──────────────────────────────

async def _provision_session(game_id: int):
    from core.database import SessionLocal
    from services.session_manager import SessionManager
    db = SessionLocal()
    try:
        game = db.query(Game).filter(Game.id == game_id).first()
        if game:
            mgr = SessionManager(db)
            await mgr.start_session(game)
    finally:
        db.close()


async def _kill_session(game_id: int, reason: str):
    from core.database import SessionLocal
    from services.session_manager import SessionManager
    db = SessionLocal()
    try:
        game = db.query(Game).filter(Game.id == game_id).first()
        if game:
            mgr = SessionManager(db)
            await mgr.kill_session(game, reason)
    finally:
        db.close()


# ── Helpers ────────────────────────────────────────────────

def _get_or_404(db: Session, game_id: int) -> Game:
    game = db.query(Game).filter(Game.id == game_id).first()
    if not game:
        raise HTTPException(404, "Session not found")
    return game


def _game_summary(g: Game) -> dict:
    return {
        "id":         g.id,
        "name":       g.name,
        "mode":       g.mode,
        "duration":   g.duration,
        "status":     g.status,
        "difficulty": g.vuln_difficulty,
        "started_at": g.started_at,
        "ended_at":   g.ended_at,
        "created_at": g.created_at,
    }


def _game_detail(game: Game, current_user: User) -> dict:
    data = _game_summary(game)
    data["teams"] = [
        {
            "id":        t.id,
            "type":      t.type,
            "join_code": t.join_code if current_user.role == "admin" else None,
            "score":     max(0, t.score),
            "members":   len(t.members),
        }
        for t in game.teams
    ]
    data["vm_count"] = len(game.vms)
    data["network"]  = game.network_cidr
    return data
