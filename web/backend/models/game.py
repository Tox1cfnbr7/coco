from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Enum, Text, JSON
from sqlalchemy.orm import relationship
from core.database import Base
import enum


class GameMode(str, enum.Enum):
    active_directory = "active_directory"
    web_application = "web_application"
    database = "database"


class GameStatus(str, enum.Enum):
    waiting = "waiting"
    running = "running"
    ended = "ended"


class GameDuration(str, enum.Enum):
    quick = "quick"        # 2h
    standard = "standard"  # 8h
    unlimited = "unlimited"


class VMStatus(str, enum.Enum):
    creating = "creating"
    running = "running"
    stopped = "stopped"
    error = "error"


class Game(Base):
    __tablename__ = "games"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(128), nullable=False)
    mode = Column(Enum(GameMode), nullable=False)
    duration = Column(Enum(GameDuration), nullable=False)
    status = Column(Enum(GameStatus), default=GameStatus.waiting)
    network_cidr = Column(String(32), nullable=True)
    vlan_id = Column(Integer, nullable=True)
    flag_value = Column(String(128), nullable=True)
    flag_captured = Column(Boolean, default=False)
    flag_captured_at = Column(DateTime, nullable=True)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    started_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    teams = relationship("Team", back_populates="game")
    vms = relationship("VM", back_populates="game")
    events = relationship("GameEvent", back_populates="game")


class Team(Base):
    __tablename__ = "teams"

    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    type = Column(String(8), nullable=False)  # red / blue
    join_code = Column(String(16), unique=True, nullable=False)
    score = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="teams")
    members = relationship("User", back_populates="team", foreign_keys="User.team_id")


class VM(Base):
    __tablename__ = "vms"

    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    name = Column(String(128), nullable=False)
    vm_type = Column(String(64), nullable=False)   # kali, win-dc, win-client, webserver, db
    team_type = Column(String(8), nullable=False)  # red / blue
    ip_address = Column(String(32), nullable=True)
    status = Column(Enum(VMStatus), default=VMStatus.creating)
    proxmox_vmid = Column(Integer, nullable=True)
    guacamole_id = Column(String(64), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="vms")


class GameEvent(Base):
    __tablename__ = "game_events"

    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    event_type = Column(String(64), nullable=False)  # flag_attempt, vm_start, game_start, etc.
    detail = Column(Text, nullable=True)
    ip_address = Column(String(45), nullable=True)
    timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="events")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    action = Column(String(128), nullable=False)
    resource = Column(String(128), nullable=True)
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(256), nullable=True)
    detail = Column(JSON, nullable=True)
    timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="audit_logs")
