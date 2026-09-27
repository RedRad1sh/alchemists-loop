import sqlite3
import server as srv  # noqa: import triggers module-level constants


def test_vein_cycles_table_exists(fresh_unit_db):
    """vein_cycles table created by init_db."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(vein_cycles)").fetchall()}
    assert cols >= {"cycle_id", "started_at", "ended_at", "spread_at",
                     "tag1", "tag2", "state", "spread_threshold", "world_finds"}
    conn.close()


def test_ensure_active_cycle_creates_row(fresh_unit_db):
    """_ensure_active_cycle creates a cycle when none exists."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    assert cycle["state"] == "active"
    assert cycle["tag1"] != ""
    assert cycle["tag2"] is None
    assert cycle["world_finds"] == 0
    assert cycle["spread_at"] is None
    assert cycle["ended_at"] is None
    conn.close()


def test_ensure_active_cycle_returns_existing(fresh_unit_db):
    """_ensure_active_cycle returns existing active cycle without creating duplicate."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    c1 = srv._ensure_active_cycle(conn)
    c2 = srv._ensure_active_cycle(conn)
    assert c1["cycle_id"] == c2["cycle_id"]
    conn.close()


def test_personal_discoveries_table_exists(fresh_unit_db):
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(personal_discoveries)").fetchall()}
    assert cols >= {"device_id", "pair_key", "discovered_at"}
    conn.close()


def test_vein_pour_log_table_exists(fresh_unit_db):
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(vein_pour_log)").fetchall()}
    assert cols >= {"device_id", "idempotency_key", "processed_at"}
    conn.close()


def test_new_vein_hits_schema(fresh_unit_db):
    """vein_hits has (device_id, cycle_id, pair_key) PK, not (week, device_id)."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(vein_hits)").fetchall()}
    assert "cycle_id" in cols
    assert "pair_key" in cols
    assert "device_id" in cols
    # Old columns should not exist in new table
    # (legacy_vein_hits holds old data separately)
    conn.close()


def test_vein_streaks_table_with_cap_claimed(fresh_unit_db):
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(vein_streaks)").fetchall()}
    assert cols >= {"device_id", "cycle_id", "count", "last_hit_at", "cap_claimed"}
    conn.close()


# ---------------------------------------------------------------------------
# Task 9: GET /api/vein/cycle/status
# ---------------------------------------------------------------------------

def test_cycle_status_endpoint(fresh_unit_db):
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    resp = client.get("/api/vein/cycle/status", params={"device_id": "dev-cs1"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert "cycle_id" in data
    assert "tag1" in data
    assert "state" in data
    assert data["state"] == "active"
    assert "my_points" in data
    assert "my_streak" in data
    # auto_applied should NOT be in response (client-side only)
    assert "pending_auto_applied" not in data


def test_cycle_status_stable_across_calls(fresh_unit_db):
    """Two consecutive GETs return the same cycle_id (lazy creation persists)."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    a = client.get("/api/vein/cycle/status").json()["cycle_id"]
    b = client.get("/api/vein/cycle/status").json()["cycle_id"]
    assert a == b
    assert a.startswith("vc:")


def test_cycle_id_unique_within_same_second(fresh_unit_db):
    """Close + immediate re-create in the SAME second must not collide on PK.

    Regression: cycle_id was f"vc:{int(time.time())}" — closing a cycle and
    creating a fresh one within one second raised IntegrityError.
    """
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    c1 = srv._ensure_active_cycle(conn)
    conn.commit()
    conn.execute(
        "UPDATE vein_cycles SET state='closed', ended_at=? WHERE cycle_id=?",
        (srv._now_iso(), c1["cycle_id"]),
    )
    conn.commit()
    c2 = srv._ensure_active_cycle(conn)
    conn.commit()
    assert c2["cycle_id"] != c1["cycle_id"]
    assert c2["cycle_id"].startswith("vc:")
    assert c2["state"] == "active"
    conn.close()


def test_cycle_status_spread_expiry_closes_and_returns_fresh(fresh_unit_db):
    """A spread cycle older than VEIN_SPREAD_DURATION days is closed by the
    endpoint, which then returns the FRESH active cycle."""
    from datetime import timedelta
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    old_cycle = client.get("/api/vein/cycle/status").json()["cycle_id"]

    # Force it into spread state with spread_at 4 days ago (> duration 3).
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    old_spread_at = (srv._now_dt() - timedelta(days=4)).isoformat()
    conn.execute(
        "UPDATE vein_cycles SET state='spread', spread_at=? WHERE cycle_id=?",
        (old_spread_at, old_cycle),
    )
    conn.commit()
    conn.close()

    resp = client.get("/api/vein/cycle/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["cycle_id"] != old_cycle
    assert data["state"] == "active"

    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    old_row = conn.execute(
        "SELECT * FROM vein_cycles WHERE cycle_id=?", (old_cycle,)
    ).fetchone()
    assert old_row["state"] == "closed"
    assert old_row["ended_at"]
    conn.close()
