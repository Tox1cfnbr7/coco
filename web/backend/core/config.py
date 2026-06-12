from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    database_url: str
    redis_url: str = "redis://localhost:6379"

    proxmox_host:     str = "localhost"
    proxmox_user:     str = "root@pam"
    proxmox_password: str = ""
    proxmox_node:     str = "pve"

    coco_repo_dir: str = "/opt/coco/repo"

    coco_ip: str = "0.0.0.0"
    coco_port: int = 443
    ssl_cert: str = "/opt/coco/ssl/coco.crt"
    ssl_key: str = "/opt/coco/ssl/coco.key"

    max_login_attempts: int = 5
    lockout_minutes: int = 15

    class Config:
        env_file = "/opt/coco/.env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    return Settings()
