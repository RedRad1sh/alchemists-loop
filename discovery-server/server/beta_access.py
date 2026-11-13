"""Closed-beta boundary. Credentials are never persisted in plaintext.

The raw ASGI guard buffers and replays a bounded body, without consuming a
Starlette Request stream. Actor policy is deliberately generic: every top-level
query/JSON device_id is the actor, never peer_device, to, or a house nickname.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
from urllib.parse import parse_qsl

from fastapi import Request
from starlette.responses import JSONResponse, RedirectResponse
from starlette.concurrency import run_in_threadpool

MAX_BODY = 2 * 1024 * 1024  # sync packages; bounded even for chunked requests
SOURCE_LIMIT = 10
GLOBAL_LIMIT = 100
RATE_BUCKETS = 256
RATE_SECONDS = 600
PRODUCT_IDS = frozenset({
    "ether_pack_small", "ether_pack_large", "sage_gold_pack",
    "starter_bundle", "remove_ads",
})  # IDs (not store SKUs) from alchemists-loop/data/monetization.json

SCHEMA = """
CREATE TABLE IF NOT EXISTS beta_identities (
    subject TEXT PRIMARY KEY,
    secret_hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS beta_invites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code_hash TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    redeemed_at REAL,
    revoked_at REAL,
    subject TEXT,
    attempt_hash TEXT
);
CREATE TABLE IF NOT EXISTS beta_sessions (
    token_hash TEXT PRIMARY KEY,
    invite_id INTEGER NOT NULL REFERENCES beta_invites(id),
    subject TEXT NOT NULL,
    created_at REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
);
CREATE INDEX IF NOT EXISTS idx_beta_sessions_invite ON beta_sessions(invite_id);
CREATE TABLE IF NOT EXISTS beta_rate_windows (
    bucket INTEGER PRIMARY KEY,
    window INTEGER NOT NULL,
    attempts INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS beta_purchases (
    subject TEXT NOT NULL,
    operation_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    purchase_id TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    granted_at REAL,
    PRIMARY KEY (subject, operation_id)
);
"""


def enabled() -> bool:
    return os.environ.get("ALCHEMY_BETA") == "1"


def validate_config(default_db_path: str, actual_db_path: str | None = None) -> None:
    """Must run before resolving/copying a legacy DB and before init_db."""
    if not enabled():
        return
    explicit = os.environ.get("ALCHEMY_DB_PATH") or os.environ.get("DB_PATH")
    if not explicit or not os.path.isabs(explicit):
        raise RuntimeError("Beta requires an explicit absolute DB_PATH (or ALCHEMY_DB_PATH)")
    if any(os.environ.get(k) == "1" for k in ("ALCHEMY_DEBUG", "ALCHEMY_ADMIN_OPEN")):
        raise RuntimeError("Beta forbids ALCHEMY_DEBUG and ALCHEMY_ADMIN_OPEN")
    target = Path(actual_db_path or explicit).resolve()
    forbidden = [Path(default_db_path).resolve(), Path(__file__).with_name("discoveries.db").resolve()]
    for normal in forbidden:
        if target == normal or (target.exists() and normal.exists() and os.path.samefile(target, normal)):
            raise RuntimeError("Beta requires an isolated database, not the ordinary database path")


def init_schema(conn: sqlite3.Connection) -> None:
    # Execute separately, not executescript: do not implicitly commit a caller's transaction.
    for statement in SCHEMA.split(";"):
        if statement.strip():
            conn.execute(statement)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalize_code(code: str) -> str:
    return code.replace("-", "").replace(" ", "").upper()


def create_invite(conn: sqlite3.Connection) -> str:
    raw = secrets.token_hex(20).upper()  # 160 random bits, human-friendly groups
    code = "-".join(raw[i:i + 8] for i in range(0, len(raw), 8))
    conn.execute("INSERT INTO beta_invites(code_hash, created_at) VALUES (?, ?)",
                 (digest(normalize_code(code)), time.time()))
    conn.commit()
    return code


def revoke_invite(conn: sqlite3.Connection, invite_id: int) -> None:
    with conn:
        conn.execute("UPDATE beta_invites SET revoked_at=COALESCE(revoked_at, ?) WHERE id=?",
                     (time.time(), invite_id))
        conn.execute("UPDATE beta_sessions SET status='revoked' WHERE invite_id=?", (invite_id,))


def delete_access(conn: sqlite3.Connection, subject: str, token_hash: str) -> None:
    """Part of the account deletion transaction, including an already-missing account.

    Keep hashes for anti-replay; only the initiating token can retry DELETE.
    Admin revocation changes even deletion-only tokens to revoked.
    """
    conn.execute("UPDATE beta_invites SET revoked_at=COALESCE(revoked_at, ?) WHERE subject=?",
                 (time.time(), subject))
    conn.execute("UPDATE beta_sessions SET status=CASE WHEN token_hash=? AND status IN ('active','deleted') "
                 "THEN 'deleted' ELSE 'revoked' END WHERE subject=?", (token_hash, subject))
    conn.execute("DELETE FROM beta_purchases WHERE subject=?", (subject,))


def error(code: str, status: int) -> JSONResponse:
    return JSONResponse({"ok": False, "error": code}, status_code=status,
                        headers={"Cache-Control": "no-store", **({"Retry-After": str(RATE_SECONDS)} if status == 429 else {})})


def _field(data: dict, name: str, maximum: int, minimum: int = 1) -> str | None:
    value = data.get(name)
    if not isinstance(value, str) or not minimum <= len(value) <= maximum or value != value.strip():
        return None
    try:
        value.encode("utf-8")
    except UnicodeError:
        return None
    return value


def _admit(conn, source: str) -> bool:
    # Hash into a fixed number of persistent buckets: bounded independently of
    # attacker addresses and worker count. Collisions conservatively share quota.
    bucket = 1 + int(digest(source)[:8], 16) % RATE_BUCKETS
    window = int(time.time()) // RATE_SECONDS
    for key, limit in ((0, GLOBAL_LIMIT), (bucket, SOURCE_LIMIT)):
        row = conn.execute("SELECT window, attempts FROM beta_rate_windows WHERE bucket=?", (key,)).fetchone()
        if row and row[0] == window and row[1] >= limit:
            return False
    for key in (0, bucket):
        conn.execute("INSERT INTO beta_rate_windows(bucket,window,attempts) VALUES (?,?,1) "
                     "ON CONFLICT(bucket) DO UPDATE SET window=excluded.window, "
                     "attempts=CASE WHEN window=excluded.window THEN attempts+1 ELSE 1 END", (key, window))
    return True


def _activation_admission(get_db, source):
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        admitted = _admit(conn, source)
        conn.commit()
        return admitted
    finally:
        conn.close()


def _activate(get_db, data, source, admitted=False):
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        if not admitted and not _admit(conn, source):
            conn.commit()
            return error("rate_limited", 429)
        code = _field(data, "code", 128)
        subject = _field(data, "device_id", 128)
        attempt = _field(data, "attempt_secret", 256, 43)
        identity = _field(data, "identity_secret", 256, 43)
        if not code or not subject or not attempt or not identity:
            conn.commit()
            return error("invalid_invite", 403)
        row = conn.execute("SELECT id, revoked_at, subject, attempt_hash FROM beta_invites WHERE code_hash=?",
                           (digest(normalize_code(code)),)).fetchone()
        if not row or row[1] is not None or (row[2] is not None and (row[2] != subject or not secrets.compare_digest(row[3] or "", digest(attempt)))):
            conn.commit()
            return error("invalid_invite", 403)
        owner = conn.execute("SELECT secret_hash FROM beta_identities WHERE subject=?", (subject,)).fetchone()
        if owner:
            owned = secrets.compare_digest(owner[0], digest(identity))
        else:
            owned = not conn.execute("SELECT 1 FROM players WHERE device_id=?", (subject,)).fetchone() and not conn.execute(
                "SELECT 1 FROM beta_invites WHERE subject=?", (subject,)).fetchone()
        if not owned:
            conn.commit()
            return error("invalid_invite", 403)
        if not owner:
            conn.execute("INSERT INTO beta_identities(subject,secret_hash) VALUES (?,?)", (subject, digest(identity)))
        token = secrets.token_urlsafe(32)
        # Rotation deletes old attempt tokens rather than retaining an unbounded retry history.
        conn.execute("DELETE FROM beta_sessions WHERE invite_id=?", (row[0],))
        conn.execute("UPDATE beta_invites SET subject=?,attempt_hash=?,redeemed_at=COALESCE(redeemed_at,?) WHERE id=?",
                     (subject, digest(attempt), time.time(), row[0]))
        conn.execute("INSERT INTO beta_sessions(token_hash,invite_id,subject,created_at) VALUES (?,?,?,?)",
                     (digest(token), row[0], subject, time.time()))
        conn.commit()
        return JSONResponse({"ok": True, "beta": True, "token": token, "device_id": subject},
                            headers={"Cache-Control": "no-store"})
    finally:
        conn.close()


def _purchase(get_db, data, granted=False):
    subject = _field(data, "device_id", 128)
    operation = _field(data, "operation_id", 128)
    product = _field(data, "product_id", 128)
    if not subject or not operation or (not granted and product not in PRODUCT_IDS):
        return error("invalid_purchase", 403)
    conn = get_db()
    try:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT product_id,purchase_id,granted_at FROM beta_purchases WHERE subject=? AND operation_id=?",
                           (subject, operation)).fetchone()
        if granted:
            if not row:
                return error("unknown_operation", 403)
            conn.execute("UPDATE beta_purchases SET granted_at=COALESCE(granted_at,?) WHERE subject=? AND operation_id=?",
                         (time.time(), subject, operation))
            conn.commit()
            return JSONResponse({"ok": True})
        if row and row[0] != product:
            return error("operation_conflict", 403)
        if not row:
            purchase_id = "beta_test:" + secrets.token_hex(32)
            conn.execute("INSERT INTO beta_purchases(subject,operation_id,product_id,purchase_id,created_at) VALUES (?,?,?,?,?)",
                         (subject, operation, product, purchase_id, time.time()))
            row = (product, purchase_id, None)
        conn.commit()
        return JSONResponse({"ok": True, "beta": True, "provider": "beta_test", "token": row[1],
                             "product_id": row[0], "already_granted": row[2] is not None},
                            headers={"Cache-Control": "no-store"})
    finally:
        conn.close()


def _session(get_db, token_hash):
    conn = get_db()
    try:
        row = conn.execute("SELECT s.subject,s.status,i.revoked_at FROM beta_sessions s "
                           "JOIN beta_invites i ON i.id=s.invite_id WHERE s.token_hash=?", (token_hash,)).fetchone()
        if not row or row[1] not in ("active", "deleted") or (row[2] is not None and row[1] != "deleted"):
            return None
        return row[0], row[1]
    finally:
        conn.close()


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


class BetaGuard:
    def __init__(self, app, get_db, admin_authenticated):
        self.app, self.get_db, self.admin_authenticated = app, get_db, admin_authenticated

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not enabled():
            return await self.app(scope, receive, send)
        path, method = scope["path"], scope["method"]
        if (path, method) == ("/api/health", "GET"):
            return await self.app(scope, receive, send)
        if not (path == "/api" or path.startswith("/api/")):
            if path.startswith("/static/") or path == "/admin/login":
                return await self.app(scope, receive, send)
            if not self.admin_authenticated(Request(scope)):
                return await RedirectResponse("/admin/login", status_code=302)(scope, receive, send)
            return await self.app(scope, receive, send)
        if path == "/api/admin" or path.startswith("/api/admin/"):
            # Separate authority even for newly added administrative APIs.
            headers = Request(scope).headers.getlist("x-admin-token")
            expected = os.environ.get("ADMIN_API_TOKEN", "")
            if len(headers) != 1 or not expected or not secrets.compare_digest(headers[0].encode(), expected.encode()):
                return await error("forbidden", 403)(scope, receive, send)
            return await self.app(scope, receive, send)
        activation = (path, method) == ("/api/beta/activate", "POST")
        session, token_hash = None, None
        if activation:
            # Include malformed and oversized attempts; otherwise invalid inputs
            # could bypass the durable limiter before endpoint validation.
            source = scope.get("client", ("unknown", 0))[0] if scope.get("client") else "unknown"
            try:
                admitted = await run_in_threadpool(_activation_admission, self.get_db, source)
            except sqlite3.Error:
                return await error("unavailable", 503)(scope, receive, send)
            if not admitted:
                return await error("rate_limited", 429)(scope, receive, send)
        if not activation:
            headers = Request(scope).headers.getlist("authorization")
            if len(headers) != 1 or not headers[0].startswith("Bearer ") or len(headers[0]) > 256:
                return await error("unauthorized", 401)(scope, receive, send)
            token_hash = digest(headers[0][7:])
            try:
                session = await run_in_threadpool(_session, self.get_db, token_hash)
            except sqlite3.Error:
                return await error("unavailable", 503)(scope, receive, send)
            if not session:
                return await error("unauthorized", 401)(scope, receive, send)
        # Bound before decoding and retain the exact bytes for downstream validation.
        raw = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            raw.extend(message.get("body", b""))
            if len(raw) > MAX_BODY:
                return await error("invalid_request", 403)(scope, receive, send)
            if not message.get("more_body", False):
                break
        try:
            pairs = parse_qsl(scope.get("query_string", b"").decode("latin-1"), keep_blank_values=True, max_num_fields=1000)
            actors = [v for k, v in pairs if k == "device_id"]
            if len(actors) > 1:
                raise ValueError("duplicate query actor")
            data = json.loads(bytes(raw), object_pairs_hook=_unique_object) if raw else {}
            if not isinstance(data, dict):
                raise ValueError("expected JSON object")
            if "device_id" in data:
                if actors:
                    raise ValueError("actor in both query and body")
                actors.append(data["device_id"])
            if session and any(not isinstance(actor, str) or actor != session[0] for actor in actors):
                raise ValueError("actor mismatch")
        except (ValueError, UnicodeError, RecursionError):
            return await error("invalid_request", 403)(scope, receive, send)
        if session:
            # Exact deletion retry: no body, other query fields, or duplicate actor.
            if session[1] == "deleted":
                if not (method == "DELETE" and path == "/api/account" and not raw and pairs == [("device_id", session[0])]):
                    return await error("unauthorized", 401)(scope, receive, send)
                # The original deletion committed atomically with this status.
                # Do NOT run account deletion again: a new invite may already
                # have created a new profile for the same device identifier.
                return await JSONResponse({"ok": True, "deleted": False, "device_id": session[0],
                                           "message": "Профиль уже удалён"},
                                          headers={"Cache-Control": "no-store"})(scope, receive, send)
            scope.setdefault("state", {}).update(beta_device_id=session[0], beta_token_hash=token_hash)
        scope.setdefault("state", {})["beta_json"] = data
        replayed = False
        async def replay():
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": bytes(raw), "more_body": False}
            return await receive()
        return await self.app(scope, replay, send)


def install(app, get_db, default_db_path, admin_authenticated):
    app.add_middleware(BetaGuard, get_db=get_db, admin_authenticated=admin_authenticated)

    @app.post("/api/beta/activate")
    async def activate(request: Request):
        if not enabled():
            return error("not_found", 404)
        # ASGI peer only. Never inspect X-Forwarded-For here.
        source = request.client.host if request.client else "unknown"
        try:
            return await run_in_threadpool(_activate, get_db, request.state.beta_json, source, True)
        except sqlite3.Error:
            return error("unavailable", 503)

    @app.post("/api/beta/purchase")
    async def purchase(request: Request):
        if not enabled():
            return error("not_found", 404)
        try:
            return await run_in_threadpool(_purchase, get_db, request.state.beta_json)
        except sqlite3.Error:
            return error("unavailable", 503)

    @app.post("/api/beta/purchase/granted")
    async def granted(request: Request):
        if not enabled():
            return error("not_found", 404)
        try:
            return await run_in_threadpool(_purchase, get_db, request.state.beta_json, True)
        except sqlite3.Error:
            return error("unavailable", 503)
