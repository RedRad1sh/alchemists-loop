"""Админ-панель — управление сервером."""
import os
import secrets
from datetime import datetime, timedelta, timezone
from functools import wraps

from fastapi import APIRouter, Request, Response, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(prefix="/admin")
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))

ADMIN_USER = os.environ.get("ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("ADMIN_PASS", "")
COOKIE_NAME = "admin_session"
COOKIE_MAX_AGE = 86400

_sessions: dict[str, float] = {}


def _check_auth(username: str, password: str) -> bool:
    if not ADMIN_PASS:
        return False
    return secrets.compare_digest(username, ADMIN_USER) and secrets.compare_digest(password, ADMIN_PASS)


def _is_authenticated(request: Request) -> bool:
    session_id = request.cookies.get(COOKIE_NAME)
    if not session_id:
        return False
    created = _sessions.get(session_id)
    if not created:
        return False
    if time.time() - created > COOKIE_MAX_AGE:
        del _sessions[session_id]
        return False
    return True


def _require_auth(handler):
    @wraps(handler)
    def wrapper(request: Request, **kwargs):
        if not _is_authenticated(request):
            return RedirectResponse("/admin/login", status_code=302)
        return handler(request, **kwargs)
    return wrapper


import time


def setup_admin(app, get_db):
    @app.get("/admin/login", response_class=HTMLResponse)
    def admin_login_page(request: Request):
        return templates.TemplateResponse("admin/login.html", {"request": request, "error": None})

    @app.post("/admin/login")
    def admin_login(
        request: Request,
        username: str = Form(...),
        password: str = Form(...),
    ):
        if _check_auth(username, password):
            session_id = secrets.token_urlsafe(32)
            _sessions[session_id] = time.time()
            response = RedirectResponse("/admin", status_code=303)
            response.set_cookie(COOKIE_NAME, session_id, max_age=COOKIE_MAX_AGE, httponly=True)
            return response
        return templates.TemplateResponse(
            "admin/login.html", {"request": request, "error": "Неверный логин или пароль"}
        )

    @app.get("/admin/logout")
    def admin_logout(request: Request):
        session_id = request.cookies.get(COOKIE_NAME)
        if session_id and session_id in _sessions:
            del _sessions[session_id]
        response = RedirectResponse("/admin/login", status_code=302)
        response.delete_cookie(COOKIE_NAME)
        return response

    @app.get("/admin", response_class=HTMLResponse)
    @_require_auth
    def admin_index(request: Request):
        return RedirectResponse("/admin/players", status_code=302)

    @app.post("/admin")
    @_require_auth
    def admin_index_post(request: Request):
        return RedirectResponse("/admin/players", status_code=303)

    @app.get("/admin/players", response_class=HTMLResponse)
    @_require_auth
    def admin_players(request: Request, q: str = "", offset: int = 0, limit: int = 50):
        conn = get_db()
        try:
            if q:
                players = conn.execute(
                    """
                    SELECT p.nick, p.device_id, p.created_at,
                           COUNT(r.id) as discovery_count
                    FROM players p
                    LEFT JOIN recipes r ON r.discoverer_device = p.device_id
                    WHERE p.nick LIKE ? OR p.device_id LIKE ?
                    GROUP BY p.device_id
                    ORDER BY p.created_at DESC
                    LIMIT ? OFFSET ?
                    """,
                    (f"%{q}%", f"%{q}%", limit, offset),
                ).fetchall()
                total = conn.execute(
                    "SELECT COUNT(*) FROM players WHERE nick LIKE ? OR device_id LIKE ?",
                    (f"%{q}%", f"%{q}%"),
                ).fetchone()[0]
            else:
                players = conn.execute(
                    """
                    SELECT p.nick, p.device_id, p.created_at,
                           COUNT(r.id) as discovery_count
                    FROM players p
                    LEFT JOIN recipes r ON r.discoverer_device = p.device_id
                    GROUP BY p.device_id
                    ORDER BY p.created_at DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()
                total = conn.execute("SELECT COUNT(*) FROM players").fetchone()[0]
            return templates.TemplateResponse(
                "admin/players.html",
                {"request": request, "players": [dict(p) for p in players], "query": q, "offset": offset, "limit": limit, "total": total},
            )
        finally:
            conn.close()

    @app.get("/admin/elements", response_class=HTMLResponse)
    @_require_auth
    def admin_elements(request: Request, q: str = ""):
        conn = get_db()
        try:
            if q:
                elements = conn.execute(
                    """
                    SELECT e.*, r.a, r.b
                    FROM elements e
                    LEFT JOIN recipes r ON r.out_id = e.id
                    WHERE e.name LIKE ?
                    ORDER BY e.layer, e.id
                    LIMIT 200
                    """,
                    (f"%{q}%",),
                ).fetchall()
            else:
                elements = conn.execute(
                    """
                    SELECT e.*, r.a, r.b
                    FROM elements e
                    LEFT JOIN recipes r ON r.out_id = e.id
                    ORDER BY e.layer, e.id
                    LIMIT 200
                    """,
                ).fetchall()
            return templates.TemplateResponse(
                "admin/elements.html",
                {"request": request, "elements": [dict(e) for e in elements], "query": q},
            )
        finally:
            conn.close()

    @app.get("/admin/events", response_class=HTMLResponse)
    @_require_auth
    def admin_events(request: Request):
        conn = get_db()
        try:
            events = conn.execute(
                "SELECT * FROM world_events ORDER BY created_at DESC LIMIT 50"
            ).fetchall()
            return templates.TemplateResponse(
                "admin/events.html",
                {"request": request, "events": [dict(e) for e in events]},
            )
        finally:
            conn.close()

    @app.post("/admin/events/create")
    @_require_auth
    def admin_create_event(
        request: Request,
        event_type: str = Form(...),
        duration_hours: int = Form(24),
    ):
        # Упрощённая версия: world_events хранит конкретные открытия, не абстрактные события
        # Для MVP просто показываем существующие события
        return RedirectResponse("/admin/events", status_code=302)

    @app.post("/admin/events/{event_id}/close")
    @_require_auth
    def admin_close_event(request: Request, event_id: int):
        # world_events не имеет статуса закрытия — оставляем как есть
        return RedirectResponse("/admin/events", status_code=302)

    @app.post("/admin/actions/reset-day")
    @_require_auth
    def admin_reset_day(request: Request):
        conn = get_db()
        try:
            today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            conn.execute("DELETE FROM challenges WHERE day_key = ?", (today,))
            conn.execute("DELETE FROM letters WHERE day_key = ?", (today,))
            conn.commit()
        finally:
            conn.close()
        return RedirectResponse("/admin/events", status_code=302)
