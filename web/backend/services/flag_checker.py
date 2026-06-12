"""
COCO — Flag Checker Background Task
Runs every CHECK_INTERVAL seconds, checks all running game services,
updates scores and downtime counters.
"""

import asyncio
import logging
from datetime import datetime, timezone

logger = logging.getLogger("coco.flag_checker")

CHECK_INTERVAL = 300   # 5 minutes


async def flag_checker_loop():
    """
    Long-running coroutine, started once at app startup via lifespan.
    Checks all running games on each tick.
    """
    logger.info("Flag checker started (interval: %ds)", CHECK_INTERVAL)
    while True:
        await asyncio.sleep(CHECK_INTERVAL)
        try:
            await _run_checks()
        except Exception as e:
            logger.error("Flag checker error: %s", e)


async def _run_checks():
    from core.database import SessionLocal
    from models.game import Game, GameStatus
    from services.session_manager import SessionManager

    db = SessionLocal()
    try:
        running_games = db.query(Game).filter(
            Game.status == GameStatus.running
        ).all()

        if not running_games:
            return

        logger.info("Checking %d running game(s)...", len(running_games))

        for game in running_games:
            try:
                mgr     = SessionManager(db)
                results = await mgr.run_flag_checker(game)
                logger.info(
                    "Game %d: %d services checked — %d up, %d down",
                    game.id, results["checked"], results["up"], results["down"]
                )
            except Exception as e:
                logger.error("Check failed for game %d: %s", game.id, e)

    finally:
        db.close()
