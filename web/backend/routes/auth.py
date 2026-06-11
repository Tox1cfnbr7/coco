from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr, field_validator
from core.database import get_db
from core.security import (
    hash_password, verify_password, create_access_token,
    check_brute_force, record_failed_login, clear_failed_logins,
    get_current_user
)
from models.user import User, UserRole, TeamType
import secrets

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    username: str
    email: EmailStr
    password: str
    team_type: TeamType
    invite_token: str

    @field_validator("username")
    @classmethod
    def username_valid(cls, v):
        if len(v) < 3 or len(v) > 32:
            raise ValueError("Username must be 3-32 characters")
        if not v.replace("_", "").replace("-", "").isalnum():
            raise ValueError("Username: only letters, numbers, - and _")
        return v.lower()

    @field_validator("password")
    @classmethod
    def password_strong(cls, v):
        if len(v) < 10:
            raise ValueError("Password must be at least 10 characters")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    username: str
    role: str
    team_type: str | None


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.invite_token == req.invite_token).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid invite token")
    if user.hashed_password:
        raise HTTPException(status_code=400, detail="Invite token already used")

    if db.query(User).filter(User.email == req.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(status_code=400, detail="Username already taken")

    user.username = req.username
    user.email = req.email
    user.hashed_password = hash_password(req.password)
    user.team_type = req.team_type
    user.invite_token = None
    db.commit()
    return {"message": "Registration successful"}


@router.post("/login", response_model=TokenResponse)
def login(req: LoginRequest, request: Request, db: Session = Depends(get_db)):
    client_ip = request.client.host
    check_brute_force(client_ip)

    user = db.query(User).filter(User.email == req.email).first()
    if not user or not user.hashed_password or not verify_password(req.password, user.hashed_password):
        record_failed_login(client_ip)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    clear_failed_logins(client_ip)
    user.last_login = datetime.now(timezone.utc)
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
        role=user.role,
        team_type=user.team_type,
    )


@router.get("/me")
def get_me(current_user: User = Depends(get_current_user)):
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "role": current_user.role,
        "team_type": current_user.team_type,
        "team_id": current_user.team_id,
    }


@router.post("/invite/generate")
def generate_invite(
    team_type: TeamType,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if current_user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Admin only")

    token = secrets.token_urlsafe(32)
    placeholder = User(
        email=f"pending_{token[:8]}@coco.local",
        username=f"pending_{token[:8]}",
        hashed_password="",
        role=UserRole.player,
        team_type=team_type,
        invite_token=token,
    )
    db.add(placeholder)
    db.commit()
    return {"invite_token": token, "team_type": team_type}
