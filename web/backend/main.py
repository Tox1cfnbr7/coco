from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import asyncio
import logging
import os

from core.config import get_settings
from core.database import engine, Base
from routes import auth, games, admin, guacamole, sessions

settings = get_settings()
logger   = logging.getLogger("coco")
limiter  = Limiter(key_func=get_remote_address, default_limits=["60/minute"])


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create DB tables
    Base.metadata.create_all(bind=engine)

    # Start background flag checker
    from services.flag_checker import flag_checker_loop
    task = asyncio.create_task(flag_checker_loop())
    logger.info("COCO backend started")
    yield
    task.cancel()


app = FastAPI(
    title    = "COCO — Attack & Defense Platform",
    version  = os.getenv("COCO_APP_VERSION", "0.9.7"),
    docs_url = "/api/docs" if os.getenv("COCO_DEBUG") else None,
    redoc_url = None,
    lifespan  = lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins     = ["*"],
    allow_credentials = True,
    allow_methods     = ["*"],
    allow_headers     = ["*"],
)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["*"])


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"]  = "nosniff"
    response.headers["X-Frame-Options"]         = "DENY"
    response.headers["X-XSS-Protection"]        = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Referrer-Policy"]         = "strict-origin-when-cross-origin"
    return response


# ── API Routes ─────────────────────────────────────────────
app.include_router(auth.router,     prefix="/api")
app.include_router(games.router,    prefix="/api")
app.include_router(admin.router,    prefix="/api")
app.include_router(sessions.router, prefix="/api")
app.include_router(guacamole.router)


@app.get("/api/health")
def health():
    return {
        "status":  "ok",
        "version": os.getenv("COCO_APP_VERSION", "0.9.7"),
    }


# ── Frontend SPA ───────────────────────────────────────────
frontend_dist = "/opt/coco/repo/web/frontend/dist"

if os.path.exists(frontend_dist):
    assets_dir = os.path.join(frontend_dist, "assets")
    if os.path.exists(assets_dir):
        app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    async def spa_fallback(full_path: str):
        index = os.path.join(frontend_dist, "index.html")
        if os.path.exists(index):
            return FileResponse(index)
        return JSONResponse({"error": "Frontend not built"}, status_code=404)
