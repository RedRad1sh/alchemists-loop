"""Дашборд — публичная статистика сервера."""
import os
import time
from datetime import datetime, timezone

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))

_start_time = time.time()


def _get_stats(get_db) -> dict:
    conn = get_db()
    try:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        total_players = conn.execute("SELECT COUNT(*) FROM players").fetchone()[0]
        active_today = conn.execute(
            "SELECT COUNT(DISTINCT device_id) FROM players WHERE date(created_at) = ?", (today,)
        ).fetchone()[0]
        total_discoveries = conn.execute(
            "SELECT COUNT(*) FROM recipes WHERE discoverer IS NOT NULL"
        ).fetchone()[0]
        discoveries_today = conn.execute(
            "SELECT COUNT(*) FROM recipes WHERE discoverer IS NOT NULL AND date(created_at) = ?",
            (today,),
        ).fetchone()[0]
        total_elements = conn.execute("SELECT COUNT(*) FROM elements").fetchone()[0]
        total_recipes = conn.execute("SELECT COUNT(*) FROM recipes").fetchone()[0]
        active_events = conn.execute("SELECT COUNT(*) FROM world_events").fetchone()[0]
        return {
            "total_players": total_players,
            "active_today": active_today,
            "total_discoveries": total_discoveries,
            "discoveries_today": discoveries_today,
            "total_elements": total_elements,
            "total_recipes": total_recipes,
            "active_events": active_events,
        }
    finally:
        conn.close()


def _get_health(get_db, DB_PATH: str) -> dict:
    uptime_sec = int(time.time() - _start_time)
    hours, remainder = divmod(uptime_sec, 3600)
    minutes, _ = divmod(remainder, 60)
    uptime_str = f"{hours}ч {minutes}м"

    try:
        db_size = os.path.getsize(DB_PATH)
        if db_size > 1024 * 1024:
            db_size_str = f"{db_size / 1024 / 1024:.1f} МБ"
        else:
            db_size_str = f"{db_size / 1024:.1f} КБ"
    except OSError:
        db_size_str = "—"

    return {
        "uptime": uptime_str,
        "db_size": db_size_str,
        "version": "1.0.0",
    }


def _get_recent(get_db, limit: int = 20) -> list:
    conn = get_db()
    try:
        rows = conn.execute(
            """
            SELECT e.name, e.glyph, e.slug, r.a, r.b,
                   r.discoverer as author, r.created_at
            FROM recipes r
            JOIN elements e ON r.out_id = e.id
            WHERE r.discoverer IS NOT NULL
            ORDER BY r.created_at DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def setup_dashboard(app, get_db, DB_PATH: str):
    @app.get("/dashboard", response_class=HTMLResponse)
    def dashboard(request: Request):
        return templates.TemplateResponse(
            "dashboard.html",
            {
                "request": request,
                "stats": _get_stats(get_db),
                "health": _get_health(get_db, DB_PATH),
                "recent": _get_recent(get_db),
            },
        )
