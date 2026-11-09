"""Closed beta contracts. All databases and credentials are test-local."""
import concurrent.futures
import json
import secrets
import sqlite3
from pathlib import Path

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

import beta_access as beta
import server as srv


@pytest.fixture
def env(tmp_path, monkeypatch):
    path = str(tmp_path / "beta.db")
    monkeypatch.setenv("ALCHEMY_BETA", "1")
    monkeypatch.setenv("DB_PATH", path)
    monkeypatch.delenv("ALCHEMY_DB_PATH", raising=False)
    monkeypatch.delenv("ALCHEMY_DEBUG", raising=False)
    monkeypatch.delenv("ALCHEMY_ADMIN_OPEN", raising=False)
    monkeypatch.setenv("ADMIN_API_TOKEN", "test-admin-token")
    monkeypatch.setattr(srv, "DB_PATH", path)
    return path


@pytest.fixture
def client(env):
    with TestClient(srv.app, base_url="https://testserver") as client:
        yield client


def invite():
    conn = srv.get_db()
    try:
        return beta.create_invite(conn)
    finally:
        conn.close()


def activate(client, code=None, device="actor", attempt=None):
    return client.post("/api/beta/activate", json={
        "code": code or invite(), "device_id": device,
        "attempt_secret": attempt or secrets.token_urlsafe(32),
        "identity_secret": beta.digest("test-identity:" + device),
    })


def auth(client, device="actor"):
    response = activate(client, device=device)
    assert response.status_code == 200, response.text
    return {"Authorization": "Bearer " + response.json()["token"]}


def test_config_requires_explicit_isolated_path(env, monkeypatch):
    default = srv._user_data_db_path()
    beta.validate_config(default, env)
    monkeypatch.delenv("DB_PATH")
    with pytest.raises(RuntimeError):
        beta.validate_config(default, env)
    monkeypatch.setenv("DB_PATH", default)
    with pytest.raises(RuntimeError):
        beta.validate_config(default, default)
    monkeypatch.setenv("DB_PATH", env)
    for flag in ("ALCHEMY_DEBUG", "ALCHEMY_ADMIN_OPEN"):
        monkeypatch.setenv(flag, "1")
        with pytest.raises(RuntimeError):
            beta.validate_config(default, env)
        monkeypatch.delenv(flag)


def test_guard_runs_before_database_init(env, monkeypatch):
    monkeypatch.setenv("ALCHEMY_DEBUG", "1")
    calls = []
    monkeypatch.setattr(srv, "init_db", lambda: calls.append(True))
    with pytest.raises(RuntimeError):
        with TestClient(srv.app):
            pass
    assert calls == []


def test_activation_retry_rotation_single_use_and_hashes(client):
    code, attempt = invite(), secrets.token_urlsafe(32)
    first = activate(client, code, attempt=attempt)
    assert first.json() == {"ok": True, "beta": True, "token": first.json()["token"], "device_id": "actor"}
    token = first.json()["token"]
    second = activate(client, code, attempt=attempt)
    assert second.status_code == 200
    assert second.json()["token"] != token
    assert client.get("/api/world", headers={"Authorization": "Bearer " + token}).status_code == 401
    for device, secret in (("other", attempt), ("actor", secrets.token_urlsafe(32))):
        denied = activate(client, code, device, secret)
        assert denied.status_code == 403
        assert denied.json() == {"ok": False, "error": "invalid_invite"}
    conn = srv.get_db()
    dump = "\n".join(conn.iterdump())
    conn.close()
    for raw in (code, attempt, token, second.json()["token"]):
        assert raw not in dump


def test_parallel_activation_one_winner(client):
    code = invite()
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results = list(pool.map(lambda d: activate(client, code, d).status_code, ["one", "two"]))
    assert sorted(results) == [200, 403]


def test_all_routes_default_deny_exact_exemptions(client):
    assert client.get("/api/health").json() == {"ok": True, "version": "1.0.0", "beta": True}
    for route in srv.app.routes:
        if not route.path.startswith("/api/") or route.path in ("/api/health", "/api/beta/activate"):
            continue
        for method in route.methods:
            expected = 403 if route.path.startswith("/api/admin/") else 401
            assert client.request(method, route.path).status_code == expected, (method, route.path)
    for path in ("/api/new-feature", "/api/beta/activate/", "/api/health/", "/api/health/details"):
        assert client.get(path).status_code == 401
    assert client.post("/api/health").status_code == 401
    headers = auth(client)
    assert client.get("/api/world", headers=headers).status_code == 200
    assert client.post("/api/admin/sigil/reset", headers=headers).status_code == 403
    assert client.post("/api/admin/sigil/reset", headers={"X-Admin-Token": "test-admin-token"}).status_code == 200


@pytest.mark.parametrize("method,path,kwargs", [
    ("GET", "/api/account/export?device_id=other", {}),
    ("DELETE", "/api/account?device_id=other", {}),
    ("POST", "/api/me", {"json": {"device_id": "other", "nick": "Other"}}),
    ("GET", "/api/me?device_id=actor&device_id=other", {}),
    ("GET", "/api/me?device_id=other&device_id=actor", {}),
    ("POST", "/api/me", {"content": '{"device_id":"actor","device_id":"other"}'}),
    ("POST", "/api/me", {"content": '{"device_id":"other","device_id":"actor"}'}),
    ("POST", "/api/me?device_id=actor", {"json": {"device_id": "other"}}),
    ("POST", "/api/me", {"content": '{"device_id":"actor",'}),
    ("POST", "/api/me", {"json": {"device_id": ["actor"]}}),
    ("POST", "/api/me", {"content": '[{"device_id":"other"}]'}),
])
def test_actor_spoof_and_ambiguity(client, method, path, kwargs):
    headers = {**auth(client), "Content-Type": "application/json"}
    response = client.request(method, path, headers=headers, **kwargs)
    assert response.status_code == 403
    assert response.json()["ok"] is False


def test_body_replay_and_peer_not_actor(client):
    headers = auth(client)
    assert client.post("/api/me", headers=headers, json={"device_id": "actor", "nick": "Player"}).status_code == 200
    # Recipient differs, but the normal friendship policy still applies.
    result = client.post("/api/friend/remove", headers=headers, json={"device_id": "actor", "peer_device": "other"})
    assert result.status_code == 404 and result.json()["detail"] == "not_friends", result.text
    assert client.get("/api/house?nick=Another", headers=headers).status_code != 403
    # Every current actor declaration is top-level device_id, not a recipient.
    for route in srv.app.routes:
        if not route.path.startswith("/api/") or not hasattr(route, "dependant"):
            continue
        for field in route.dependant.query_params:
            if "device" in field.name:
                assert field.name in ("device_id", "peer_device")
        for field in route.dependant.body_params:
            model = getattr(field.type_, "model_fields", {})
            actor_fields = [name for name in model if "device" in name]
            assert all(name in ("device_id", "peer_device", "requester_device", "target_device") for name in actor_fields), (route.path, actor_fields)
            if actor_fields:
                assert "device_id" in model
                assert model["device_id"].alias in (None, "device_id")


def test_revoke_and_deletion_only_retry(client):
    headers = auth(client)
    assert client.post("/api/me", headers=headers, json={"device_id": "actor", "nick": "Player"}).status_code == 200
    first = client.delete("/api/account?device_id=actor", headers=headers)
    assert first.status_code == 200
    assert client.get("/api/world", headers=headers).status_code == 401
    assert client.delete("/api/account?device_id=actor", headers=headers).status_code == 200
    assert client.delete("/api/account?device_id=other", headers=headers).status_code in (401, 403)
    assert client.delete("/api/account?device_id=actor&extra=1", headers=headers).status_code in (401, 403)
    conn = srv.get_db()
    row = conn.execute("SELECT id FROM beta_invites ORDER BY id DESC LIMIT 1").fetchone()
    beta.revoke_invite(conn, row[0])
    conn.close()
    assert client.delete("/api/account?device_id=actor", headers=headers).status_code == 401
    # Even a never-registered device loses gameplay access after DELETE.
    headers = auth(client, "unregistered")
    assert client.delete("/api/account?device_id=unregistered", headers=headers).status_code == 200
    assert client.get("/api/world", headers=headers).status_code == 401


def test_rate_limit_durable_bounded_ignores_xff(client, monkeypatch):
    monkeypatch.setattr(beta, "SOURCE_LIMIT", 3)
    for i in range(3):
        response = client.post("/api/beta/activate", headers={"X-Forwarded-For": f"10.0.0.{i}"}, json={
            "code": "invalid-code", "device_id": "actor", "attempt_secret": "x" * 43})
        assert response.status_code == 403
    # New client/middleware instance, same SQLite counters.
    with TestClient(srv.app) as other:
        assert activate(other).status_code == 429
    conn = srv.get_db()
    assert conn.execute("SELECT COUNT(*) FROM beta_rate_windows").fetchone()[0] <= beta.RATE_BUCKETS + 1
    conn.close()


def test_purchases_allowlist_idempotency_grants_and_receipt_separation(client):
    headers = auth(client)
    payload = {"device_id": "actor", "operation_id": "op-1", "product_id": "ether_pack_small"}
    first = client.post("/api/beta/purchase", headers=headers, json=payload)
    assert first.status_code == 200
    data = first.json()
    assert data["provider"] == "beta_test" and data["beta"] is True
    assert data["token"].startswith("beta_test:") and not data["already_granted"]
    assert client.post("/api/beta/purchase", headers=headers, json=payload).json() == data
    assert client.post("/api/beta/purchase", headers=headers, json={**payload, "product_id": "remove_ads"}).status_code == 403
    assert client.post("/api/beta/purchase", headers=headers, json={**payload, "operation_id": "op-2", "product_id": "invented"}).status_code == 403
    assert client.post("/api/beta/purchase/granted", headers=headers, json={"device_id": "actor", "operation_id": "op-1"}).json() == {"ok": True}
    assert client.post("/api/beta/purchase", headers=headers, json=payload).json()["already_granted"] is True
    rejected = client.post("/api/receipt/verify", headers=headers, json={"device_id": "actor", "provider": "beta_test", "sku": "al_loop_ether_500", "receipt_token": data["token"]})
    assert rejected.status_code == 400
    catalog = Path(__file__).resolve().parents[3] / "alchemists-loop/data/monetization.json"
    assert beta.PRODUCT_IDS == frozenset(p["id"] for p in json.loads(catalog.read_text(encoding="utf-8"))["products"])


def test_admin_and_private_browser_surfaces(client, monkeypatch):
    import admin
    monkeypatch.setattr(admin, "ADMIN_PASS", "beta-test-password")
    for path in ("/", "/dashboard", "/docs", "/redoc", "/openapi.json", "/admin/beta"):
        response = client.get(path, follow_redirects=False)
        assert response.status_code in (302, 401, 403, 404), path
    login = client.post("/admin/login", data={"username": "admin", "password": "beta-test-password"}, follow_redirects=False)
    assert login.status_code == 303
    assert "Secure" in login.headers["set-cookie"] and "HttpOnly" in login.headers["set-cookie"]
    assert client.get("/dashboard").status_code == 200
    page = client.get("/admin/beta")
    assert page.status_code == 200
    assert client.post("/admin/beta/create").status_code == 403
    import re
    csrf = re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)
    assert client.post("/admin/beta/create", data={"csrf_token": "wrong"}).status_code == 403
    created = client.post("/admin/beta/create", data={"csrf_token": csrf})
    assert created.status_code == 200
    code = re.search(r'id="new-invite">([^<]+)', created.text).group(1)
    assert code not in client.get("/admin/beta").text
    headers = auth(client)
    conn = srv.get_db()
    invite_id = conn.execute("SELECT MAX(id) FROM beta_invites").fetchone()[0]
    conn.close()
    assert client.post(f"/admin/beta/{invite_id}/revoke", data={"csrf_token": csrf}).status_code == 200
    assert client.get("/api/world", headers=headers).status_code == 401


def test_normal_mode_unchanged_and_no_beta_routes(client, monkeypatch):
    monkeypatch.delenv("ALCHEMY_BETA")
    assert "beta" not in client.get("/api/health").json()
    assert client.get("/api/world").status_code == 200
    for path in ("/api/beta/activate", "/api/beta/purchase", "/api/beta/purchase/granted"):
        assert client.post(path, json={}).status_code == 404


def test_database_errors_fail_closed(client, monkeypatch):
    headers = auth(client)
    def broken():
        raise sqlite3.OperationalError("test unavailable")
    monkeypatch.setattr(srv, "get_db", broken)
    response = client.get("/api/world", headers=headers)
    assert response.status_code == 503
    assert response.json()["error"] == "unavailable"


def test_activation_cannot_claim_another_device(client):
    headers = auth(client)
    client.post("/api/me", headers=headers, json={"device_id": "actor", "nick": "Owner"})
    stolen = client.post("/api/beta/activate", json={
        "code": invite(), "device_id": "actor", "attempt_secret": secrets.token_urlsafe(32),
        "identity_secret": secrets.token_urlsafe(32),
    })
    assert stolen.status_code == 403
    assert client.get("/api/me?device_id=actor", headers=headers).json()["nick"] == "Owner"
    assert activate(client).status_code == 200
    conn = srv.get_db()
    conn.execute("INSERT INTO players(device_id,nick) VALUES ('legacy','Legacy')")
    conn.commit()
    conn.close()
    assert activate(client, device="legacy").status_code == 403


def test_guard_uses_downstream_query_decoding(client):
    import asyncio
    headers = auth(client, device="é")
    async def run():
        messages = []
        async def downstream(scope, receive, send):
            await beta.JSONResponse({"unexpected": True})(scope, receive, send)
        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}
        async def send(message):
            messages.append(message)
        scope = {"type": "http", "method": "GET", "path": "/api/account/export",
                 "query_string": b"device_id=\xc3\xa9", "headers": [(b"authorization", headers["Authorization"].encode())]}
        await beta.BetaGuard(downstream, srv.get_db, lambda request: False)(scope, receive, send)
        return messages[0]["status"]
    assert asyncio.run(run()) == 403


def test_bounded_request_body(client, monkeypatch):
    monkeypatch.setattr(beta, "MAX_BODY", 1024)
    assert client.post("/api/me", headers=auth(client), content=b"x" * 1025).status_code == 403


def test_schema_sql_and_heal_have_identical_beta_tables():
    fresh, healed = sqlite3.connect(":memory:"), sqlite3.connect(":memory:")
    try:
        schema = Path(srv.__file__).with_name("schema.sql").read_text(encoding="utf-8")
        fresh.executescript(schema)
        beta.init_schema(healed)
        beta.init_schema(healed)
        for table in ("beta_identities", "beta_invites", "beta_sessions", "beta_rate_windows", "beta_purchases"):
            assert fresh.execute(f"PRAGMA table_info({table})").fetchall() == healed.execute(f"PRAGMA table_info({table})").fetchall()
    finally:
        fresh.close()
        healed.close()


def test_revoked_unused_code_and_attempt_cannot_restore_deleted_access(client):
    code = invite()
    conn = srv.get_db()
    beta.revoke_invite(conn, conn.execute("SELECT MAX(id) FROM beta_invites").fetchone()[0])
    conn.close()
    assert activate(client, code).status_code == 403
    code, attempt = invite(), secrets.token_urlsafe(32)
    activated = activate(client, code, attempt=attempt)
    headers = {"Authorization": "Bearer " + activated.json()["token"]}
    assert client.delete("/api/account?device_id=actor", headers=headers).status_code == 200
    assert activate(client, code, attempt=attempt).status_code == 403
    new_headers = auth(client)
    assert client.post("/api/me", headers=new_headers, json={"device_id": "actor", "nick": "NewPlayer"}).status_code == 200
    assert client.delete("/api/account?device_id=actor", headers=headers).status_code == 200
    profile = client.get("/api/me?device_id=actor", headers=new_headers)
    assert profile.status_code == 200 and profile.json()["nick"] == "NewPlayer", profile.text


def test_new_routes_with_and_without_actor_are_guarded(client):
    app = FastAPI()
    beta.install(app, srv.get_db, srv._user_data_db_path(), lambda request: False)
    @app.post("/api/future")
    async def future(request: Request):
        return {"actor": request.state.beta_device_id, "body": await request.json()}
    with TestClient(app) as other:
        assert other.post("/api/future", json={}).status_code == 401
        headers = auth(client)
        assert other.post("/api/future", headers=headers, json={"device_id": "other"}).status_code == 403
        assert other.post("/api/future", headers=headers, json={"peer_device": "other", "to": "other"}).json()["actor"] == "actor"


def test_global_rate_limit_and_bounded_source_buckets(client, monkeypatch):
    monkeypatch.setattr(beta, "GLOBAL_LIMIT", 3)
    # Real transport peers, rather than forwarding headers, share a global cap.
    for i in range(4):
        result = beta._activate(srv.get_db, {}, f"source-{i}")
        assert result.status_code == (403 if i < 3 else 429)
    monkeypatch.setattr(beta, "GLOBAL_LIMIT", 10000)
    for i in range(beta.RATE_BUCKETS * 2):
        beta._activate(srv.get_db, {}, f"more-{i}")
    conn = srv.get_db()
    assert conn.execute("SELECT COUNT(*) FROM beta_rate_windows").fetchone()[0] <= beta.RATE_BUCKETS + 1
    conn.close()


def test_malformed_activation_is_rate_limited(client, monkeypatch):
    monkeypatch.setattr(beta, "SOURCE_LIMIT", 2)
    for _ in range(2):
        assert client.post("/api/beta/activate", content='{"device_id":').status_code == 403
    assert client.post("/api/beta/activate", content='{"device_id":').status_code == 429


def test_no_raw_beta_credentials_in_export_and_revoked_purchase(client):
    code, attempt = invite(), secrets.token_urlsafe(32)
    token = activate(client, code, attempt=attempt).json()["token"]
    headers = {"Authorization": "Bearer " + token}
    client.post("/api/me", headers=headers, json={"device_id": "actor", "nick": "Player"})
    exported = client.get("/api/account/export?device_id=actor", headers=headers)
    assert exported.status_code == 200
    for raw in (code, attempt, token):
        assert raw not in exported.text
    conn = srv.get_db()
    beta.revoke_invite(conn, conn.execute("SELECT MAX(id) FROM beta_invites").fetchone()[0])
    conn.close()
    assert client.post("/api/beta/purchase", headers=headers, json={"device_id": "actor", "operation_id": "op", "product_id": "remove_ads"}).status_code == 401


def test_durable_limiter_window_reset_and_random_source_bound(client, monkeypatch):
    conn = srv.get_db()
    conn.execute("INSERT INTO beta_rate_windows(bucket,window,attempts) VALUES (0,0,100000)")
    conn.commit()
    conn.close()
    assert activate(client).status_code == 200


def test_missing_actor_and_invalid_activation_fields(client):
    for payload in ({}, {"code": "x", "device_id": "actor", "attempt_secret": "short"}):
        assert client.post("/api/beta/activate", json=payload).status_code == 403
    headers = auth(client)
    assert client.post("/api/beta/purchase", headers=headers, json={"operation_id": "x", "product_id": "remove_ads"}).status_code == 403
    assert client.post("/api/beta/purchase/granted", headers=headers, json={"device_id": "actor", "operation_id": "missing"}).status_code == 403
