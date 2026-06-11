from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Enum
from sqlalchemy.orm import relationship
from core.database import Base
import enum


class UserRole(str, enum.Enum):
    admin = "admin"
    player = "player"


class TeamType(str, enum.Enum):
    red = "red"
    blue = "blue"


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    username = Column(String(64), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    role = Column(Enum(UserRole), default=UserRole.player, nullable=False)
    team_type = Column(Enum(TeamType), nullable=True)
    team_id = Column(Integer, ForeignKey("teams.id"), nullable=True)
    invite_token = Column(String(64), unique=True, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    last_login = Column(DateTime, nullable=True)

    team = relationship("Team", back_populates="members", foreign_keys=[team_id])
    audit_logs = relationship("AuditLog", back_populates="user")
