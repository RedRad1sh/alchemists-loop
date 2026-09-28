import sqlite3
import server as srv
from fastapi.testclient import TestClient


def test_pour_success(fresh_unit_db):
    srv.init_db()
    client = TestClient(srv.app)
    resp = client.post("/api/vein/pour", json={
        "device_id": "dev-pour1",
        "idempotency_key": "uuid-abc-123",
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["already_poured"] is False
    # Verify log entry
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    log = conn.execute(
        "SELECT * FROM vein_pour_log WHERE device_id='dev-pour1' AND idempotency_key='uuid-abc-123'"
    ).fetchone()
    assert log is not None
    conn.close()


def test_pour_idempotent(fresh_unit_db):
    srv.init_db()
    client = TestClient(srv.app)
    body = {"device_id": "dev-pour2", "idempotency_key": "uuid-def-456"}
    r1 = client.post("/api/vein/pour", json=body).json()
    r2 = client.post("/api/vein/pour", json=body).json()
    assert r1["ok"] is True and r1["already_poured"] is False
    assert r2["ok"] is True and r2["already_poured"] is True
    # UI-only ceremony: never scores points → no points field in the response.
    assert "points" not in r1
    assert "points" not in r2
    conn = sqlite3.connect(srv.DB_PATH)
    n = conn.execute(
        "SELECT COUNT(*) FROM vein_pour_log WHERE device_id='dev-pour2'"
    ).fetchone()[0]
    conn.close()
    assert n == 1  # replay must not insert a second row


def test_pour_different_devices_independent(fresh_unit_db):
    srv.init_db()
    client = TestClient(srv.app)
    key = "uuid-shared-key"
    r1 = client.post("/api/vein/pour", json={"device_id": "dev-a", "idempotency_key": key}).json()
    r2 = client.post("/api/vein/pour", json={"device_id": "dev-b", "idempotency_key": key}).json()
    assert r1["ok"] is True and r1["already_poured"] is False
    assert r2["ok"] is True and r2["already_poured"] is False
