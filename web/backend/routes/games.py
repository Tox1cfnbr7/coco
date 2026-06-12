from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from core.database import get_db
from core.security import get_current_user, require_admin
from models.user import User
from models.game import Game, Team, GameEvent, GameMode, GameDuration, GameStatus
import secrets
import string

router = APIRouter(prefix="/games", tags=["games"])


def generate_join_code(length: int = 8) -> str:
    chars = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(chars) for _ in range(length))


class CreateGameRequest(BaseModel):
    name: str
    mode: GameMode
    duration: GameDuration
    network_cidr: str = "10.10.0.0/24"


class FlagSubmitRequest(BaseModel):
    flag: str


@router.get("/")
def list_games(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    games = db.query(Game).order_by(Game.created_at.desc()).limit(50).all()
    return [
        {
            "id": g.id,
            "name": g.name,
            "mode": g.mode,
            "duration": g.duration,
            "status": g.status,
            "flag_captured": g.flag_captured,
            "created_at": g.created_at,
        }
        for g in games
    ]


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_game(
    req: CreateGameRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    flag = "COCO{" + secrets.token_hex(16) + "}"
    game = Game(
        name=req.name,
        mode=req.mode,
        duration=req.duration,
        network_cidr=req.network_cidr,
        flag_value=flag,
        created_by=current_user.id,
    )
    db.add(game)
    db.flush()

    red_team = Team(game_id=game.id, type="red", join_code=generate_join_code())
    blue_team = Team(game_id=game.id, type="blue", join_code=generate_join_code())
    db.add(red_team)
    db.add(blue_team)
    db.commit()
    db.refresh(game)

    return {
        "id": game.id,
        "name": game.name,
        "mode": game.mode,
        "red_join_code": red_team.join_code,
        "blue_join_code": blue_team.join_code,
    }


@router.get("/{game_id}")
def get_game(
    game_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    game = db.query(Game).filter(Game.id == game_id).first()
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")

    teams = []
    for t in game.teams:
        teams.append({
            "id": t.id,
            "type": t.type,
            "join_code": t.join_code if current_user.role == "admin" else None,
            "score": t.score,
            "member_count": len(t.members),
        })

    vms = [
        {"id": v.id, "name": v.name, "type": v.vm_type,
         "team": v.team_type, "ip": v.ip_address, "status": v.status}
        for v in game.vms
    ]

    return {
        "id": game.id,
        "name": game.name,
        "mode": game.mode,
        "duration": game.duration,
        "status": game.status,
        "flag_captured": game.flag_captured,
        "started_at": game.started_at,
        "ended_at": game.ended_at,
        "teams": teams,
        "vms": vms,
    }


@router.post("/{game_id}/start")
async def start_game(
    game_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    game = db.query(Game).filter(Game.id == game_id).first()
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    if game.status != GameStatus.waiting:
        raise HTTPException(status_code=400, detail="Game already started or ended")

    # Start provisioning in background
    from services.game_engine import GameEngine
    import asyncio

    async def provision():
        engine = GameEngine(db)
        await engine.start_game(game)

    asyncio.create_task(provision())
    return {"message": "Game provisioning started", "game_id": game_id}


@router.post("/{game_id}/flag")
def submit_flag(
    game_id: int,
    req: FlagSubmitRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    game = db.query(Game).filter(Game.id == game_id).first()
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    if game.status != GameStatus.running:
        raise HTTPException(status_code=400, detail="Game is not running")
    if game.flag_captured:
        raise HTTPException(status_code=400, detail="Flag already captured")
    if current_user.team_type != "red":
        raise HTTPException(status_code=403, detail="Only Red Team can submit flags")

    db.add(GameEvent(
        game_id=game.id,
        user_id=current_user.id,
        event_type="flag_attempt",
        detail=f"submitted: {req.flag[:32]}",
        ip_address=request.client.host,
    ))

    if req.flag.strip() != game.flag_value:
        db.commit()
        raise HTTPException(status_code=400, detail="Wrong flag")

    game.flag_captured = True
    game.flag_captured_at = datetime.now(timezone.utc)
    game.status = GameStatus.ended
    game.ended_at = datetime.now(timezone.utc)
    db.add(GameEvent(game_id=game.id, user_id=current_user.id, event_type="flag_captured"))
    db.commit()

    return {"captured": True, "message": "Flag captured — Red Team wins!"}


@router.post("/{game_id}/join")
def join_team(
    game_id: int,
    join_code: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    team = db.query(Team).filter(
        Team.game_id == game_id,
        Team.join_code == join_code.upper()
    ).first()
    if not team:
        raise HTTPException(status_code=404, detail="Invalid join code")

    current_user.team_id = team.id
    db.commit()
    return {"message": f"Joined {team.type} team", "team_id": team.id}


@router.post("/{game_id}/surrender")
def surrender(
    game_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    game = db.query(Game).filter(Game.id == game_id).first()
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    if game.duration != "unlimited":
        raise HTTPException(status_code=400, detail="Surrender only in unlimited mode")

    game.status = GameStatus.ended
    game.ended_at = datetime.now(timezone.utc)
    db.add(GameEvent(
        game_id=game.id, user_id=current_user.id,
        event_type="surrender", detail=f"team: {current_user.team_type}"
    ))
    db.commit()
    return {"message": "Game ended by surrender"}
