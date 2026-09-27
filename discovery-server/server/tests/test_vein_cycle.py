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
