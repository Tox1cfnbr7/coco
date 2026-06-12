from datetime import datetime, timezone
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime,
    ForeignKey, Enum, Text, JSON, Float
)
from sqlalchemy.orm import relationship
from core.database import Base
import enum


# ── Enums ──────────────────────────────────────────────────

class GameMode(str, enum.Enum):
    initial_access   = "initial_access"    # DMZ → LAN, 2-3h
    full_compromise  = "full_compromise"   # Domain Admin, 4-6h
    ransomware_sim   = "ransomware_sim"    # Ransomware deploy, 4-8h
    purple_team      = "purple_team"       # Training / detection


class GameStatus(str, enum.Enum):
    waiting      = "waiting"
    provisioning = "provisioning"
    running      = "running"
    ended        = "ended"
    error        = "error"


class GameDuration(str, enum.Enum):
    quick     = "quick"      # 2h
    standard  = "standard"   # 4h
    long      = "long"       # 8h
    unlimited = "unlimited"


class VMStatus(str, enum.Enum):
    creating = "creating"
    running  = "running"
    stopped  = "stopped"
    error    = "error"


class VulnDifficulty(str, enum.Enum):
    easy   = "easy"    # 1-2 vulns per category
    medium = "medium"  # 2-3 vulns per category
    hard   = "hard"    # 3-4 vulns per category


# ── Models ─────────────────────────────────────────────────

class Game(Base):
    __tablename__ = "games"

    id              = Column(Integer, primary_key=True, index=True)
    name            = Column(String(128), nullable=False)
    mode            = Column(Enum(GameMode), nullable=False)
    duration        = Column(Enum(GameDuration), nullable=False)
    status          = Column(Enum(GameStatus), default=GameStatus.waiting)
    vuln_difficulty = Column(Enum(VulnDifficulty), default=VulnDifficulty.medium)

    # Network
    network_cidr    = Column(String(32), nullable=True)
    vlan_id         = Column(Integer, nullable=True)

    # Flags (per-service flags, not just one)
    flags_config    = Column(JSON, default=list)   # list of {service, flag, points}

    # Timing
    max_downtime_minutes = Column(Integer, default=30)  # lose if exceeded
    created_by      = Column(Integer, ForeignKey("users.id"), nullable=False)
    started_at      = Column(DateTime, nullable=True)
    ended_at        = Column(DateTime, nullable=True)
    created_at      = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    # Relations
    teams   = relationship("Team",      back_populates="game", cascade="all, delete-orphan")
    vms     = relationship("VM",        back_populates="game", cascade="all, delete-orphan")
    events  = relationship("GameEvent", back_populates="game", cascade="all, delete-orphan")
    checks  = relationship("ServiceCheck", back_populates="game", cascade="all, delete-orphan")


class Team(Base):
    __tablename__ = "teams"

    id         = Column(Integer, primary_key=True, index=True)
    game_id    = Column(Integer, ForeignKey("games.id"), nullable=False)
    type       = Column(String(8), nullable=False)   # red / blue
    join_code  = Column(String(16), unique=True, nullable=False)
    score      = Column(Integer, default=0)

    # Downtime tracking
    total_downtime_seconds = Column(Integer, default=0)
    last_downtime_start    = Column(DateTime, nullable=True)

    # Scoring breakdown
    attack_points  = Column(Integer, default=0)
    defense_points = Column(Integer, default=0)
    penalty_points = Column(Integer, default=0)

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game    = relationship("Game", back_populates="teams")
    members = relationship("User", back_populates="team", foreign_keys="User.team_id")


class VM(Base):
    __tablename__ = "vms"

    id           = Column(Integer, primary_key=True, index=True)
    game_id      = Column(Integer, ForeignKey("games.id"), nullable=False)
    team_id      = Column(Integer, ForeignKey("teams.id"), nullable=True)
    name         = Column(String(128), nullable=False)
    display_name = Column(String(128), nullable=True)   # "DC-01 (Domain Controller)"
    vm_type      = Column(String(64), nullable=False)   # kali, win-dc, win-mssql, webserver, linux
    role         = Column(String(64), nullable=True)    # dc-primary, dc-mssql, web, file, workstation
    team_type    = Column(String(8),  nullable=False)   # red / blue
    ip_address   = Column(String(32), nullable=True)
    status       = Column(Enum(VMStatus), default=VMStatus.creating)
    proxmox_vmid = Column(Integer, nullable=True)
    guacamole_id = Column(String(64), nullable=True)

    # Vulnerability injection state
    injected_vulns = Column(JSON, default=list)  # list of vuln IDs that were activated

    # Uptime tracking
    is_reachable      = Column(Boolean, default=True)
    last_check_at     = Column(DateTime, nullable=True)
    consecutive_fails = Column(Integer, default=0)

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="vms")


class ServiceCheck(Base):
    """Records every flag-checker ping result."""
    __tablename__ = "service_checks"

    id         = Column(Integer, primary_key=True, index=True)
    game_id    = Column(Integer, ForeignKey("games.id"), nullable=False)
    vm_id      = Column(Integer, ForeignKey("vms.id"), nullable=False)
    team_id    = Column(Integer, ForeignKey("teams.id"), nullable=False)
    service    = Column(String(64), nullable=False)   # http, ssh, rdp, smb, mssql
    reachable  = Column(Boolean, nullable=False)
    latency_ms = Column(Float, nullable=True)
    timestamp  = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="checks")


class CapturedFlag(Base):
    """Records each flag capture event."""
    __tablename__ = "captured_flags"

    id          = Column(Integer, primary_key=True, index=True)
    game_id     = Column(Integer, ForeignKey("games.id"), nullable=False)
    team_id     = Column(Integer, ForeignKey("teams.id"), nullable=False)
    captured_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    service     = Column(String(64), nullable=False)
    flag_value  = Column(String(256), nullable=False)
    points      = Column(Integer, nullable=False)
    captured_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class GameEvent(Base):
    __tablename__ = "game_events"

    id         = Column(Integer, primary_key=True, index=True)
    game_id    = Column(Integer, ForeignKey("games.id"), nullable=False)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=True)
    team_id    = Column(Integer, ForeignKey("teams.id"), nullable=True)
    event_type = Column(String(64), nullable=False)
    detail     = Column(Text, nullable=True)
    points     = Column(Integer, default=0)
    ip_address = Column(String(45), nullable=True)
    timestamp  = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    game = relationship("Game", back_populates="events")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=True)
    action     = Column(String(128), nullable=False)
    resource   = Column(String(128), nullable=True)
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(256), nullable=True)
    detail     = Column(JSON, nullable=True)
    timestamp  = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="audit_logs")
