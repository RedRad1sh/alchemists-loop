import sqlite3

import pytest

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


def test_cycle_status_my_points_scoped_to_cycle(fresh_unit_db):
    """my_points sums ONLY this device's vein_points rows with day >= cycle start."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    cycle_id = client.get("/api/vein/cycle/status").json()["cycle_id"]
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    started = conn.execute(
        "SELECT started_at FROM vein_cycles WHERE cycle_id=?", (cycle_id,)
    ).fetchone()["started_at"][:10]
    srv._add_vein_points(conn, srv._today(), "dev-mp", "nick", 2)
    old_day = "2000-01-01"
    assert old_day < started  # pre-cycle row must exist strictly before the window
    srv._add_vein_points(conn, old_day, "dev-mp", "nick", 5)
    conn.commit()
    conn.close()
    data = client.get("/api/vein/cycle/status",
                      params={"device_id": "dev-mp"}).json()
    assert data["my_points"] == 2


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


# ---------------------------------------------------------------------------
# Task 10: CAS-переходы цикла active→spread→closed
# ---------------------------------------------------------------------------

def test_spread_transition_cas(fresh_unit_db):
    """active→spread sets tag2 and spread_at atomically."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    # Simulate threshold reached
    conn.execute(
        "UPDATE vein_cycles SET world_finds=? WHERE cycle_id=?",
        (cycle["spread_threshold"], cycle["cycle_id"]),
    )
    cycle["world_finds"] = cycle["spread_threshold"]
    srv._maybe_spread_cycle(conn, cycle)
    updated = conn.execute(
        "SELECT * FROM vein_cycles WHERE cycle_id=?", (cycle["cycle_id"],)
    ).fetchone()
    assert updated["state"] == "spread"
    assert updated["tag2"] is not None
    assert updated["spread_at"] is not None
    # вызванный dict тоже мутирован (контракт _maybe_spread_cycle)
    assert cycle["state"] == "spread"
    assert cycle["tag2"] == updated["tag2"]
    conn.close()


def test_closed_transition_after_spread_duration(fresh_unit_db):
    """spread→closed after VEIN_SPREAD_DURATION days."""
    from datetime import date as _date, timedelta
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    # Force spread state with old spread_at (единая серверная шкала — _now_dt)
    old_spread = (srv._now_dt() - timedelta(days=4)).isoformat()
    conn.execute(
        "UPDATE vein_cycles SET state='spread', tag2='secondary', spread_at=? WHERE cycle_id=?",
        (old_spread, cycle["cycle_id"]),
    )
    conn.commit()
    # Trigger via cycle_status-like check
    spread_row = conn.execute(
        "SELECT * FROM vein_cycles WHERE cycle_id=?", (cycle["cycle_id"],)
    ).fetchone()
    spread_date = _date.fromisoformat(spread_row["spread_at"][:10])
    today = srv._today_date()
    assert (today - spread_date).days >= srv.VEIN_SPREAD_DURATION
    cursor = conn.execute(
        "UPDATE vein_cycles SET state='closed', ended_at=? WHERE cycle_id=? AND state='spread'",
        (srv._now_iso(), cycle["cycle_id"]),
    )
    assert cursor.rowcount == 1
    conn.commit()
    # Guard check: re-run must match NOTHING (state is 'closed' now).
    # Without `AND state='spread'` this UPDATE would re-stamp ended_at.
    again = conn.execute(
        "UPDATE vein_cycles SET state='closed', ended_at=? WHERE cycle_id=? AND state='spread'",
        (srv._now_iso(), cycle["cycle_id"]),
    )
    assert again.rowcount == 0
    conn.commit()
    # New active cycle should be creatable
    new_cycle = srv._ensure_active_cycle(conn)
    assert new_cycle["cycle_id"] != cycle["cycle_id"]
    assert new_cycle["state"] == "active"
    conn.close()


def test_spread_cas_loss_rereads_winner_tag2(fresh_unit_db, monkeypatch):
    """CAS-loss (state changed between re-read and UPDATE) must not clobber
    the winner's tag2 — _maybe_spread_cycle falls back to re-reading it."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    conn.execute(
        "UPDATE vein_cycles SET world_finds=? WHERE cycle_id=?",
        (cycle["spread_threshold"], cycle["cycle_id"]),
    )
    conn.commit()

    real_pick = srv._cycle_pick

    def racing_pick(c, exclude=None):
        # Between the function's re-read and its CAS UPDATE another writer
        # transitions the row — our UPDATE must then hit rowcount == 0.
        other = sqlite3.connect(srv.DB_PATH)
        other.execute(
            "UPDATE vein_cycles SET state='spread', tag2='racer-tag', spread_at=? "
            "WHERE cycle_id=? AND state='active'",
            (srv._now_iso(), cycle["cycle_id"]),
        )
        other.commit()
        other.close()
        return real_pick(c, exclude=exclude)

    monkeypatch.setattr(srv, "_cycle_pick", racing_pick)
    srv._maybe_spread_cycle(conn, cycle)
    assert cycle["tag2"] == "racer-tag"  # fallback re-read, not our picked tag
    row = conn.execute(
        "SELECT * FROM vein_cycles WHERE cycle_id=?", (cycle["cycle_id"],)
    ).fetchone()
    assert row["tag2"] == "racer-tag"  # winner's value intact
    conn.close()


# ---------------------------------------------------------------------------
# Финальное ревью (F2): один открытый цикл гарантирован на уровне БД —
# частичный UNIQUE-индекс ux_vein_cycles_one_open + race-tolerant
# _ensure_active_cycle (uuid-суффикс PK снял случайную защиту от коллизий,
# два конкурента могли создать по открытому циклу).
# ---------------------------------------------------------------------------

def _close_all_open_cycles(conn):
    """Свежий старт: коммит-тесты предыдущих кейсов могут оставить открытый
    цикл в module-scoped БД — закрываем все open-ряды перед ассертами."""
    conn.execute(
        "UPDATE vein_cycles SET state='closed', ended_at=? "
        "WHERE state IN ('active', 'spread')",
        (srv._now_iso(),),
    )
    conn.commit()


def test_one_open_cycle_unique_index(fresh_unit_db):
    """Прямой INSERT второго открытого цикла — IntegrityError, пока первый активен."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    _close_all_open_cycles(conn)
    c1 = srv._ensure_active_cycle(conn)
    conn.commit()
    assert c1["state"] == "active"
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "INSERT INTO vein_cycles (cycle_id, started_at, tag1, state, spread_threshold) "
            "VALUES (?, ?, ?, 'active', 20)",
            ("vc:second-active", srv._now_iso(), c1["tag1"]),
        )
    # spread тоже «открытый» state — второй открытый ряд недопустим и в spread
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "INSERT INTO vein_cycles (cycle_id, started_at, tag1, state, spread_threshold) "
            "VALUES (?, ?, ?, 'spread', 20)",
            ("vc:second-spread", srv._now_iso(), c1["tag1"]),
        )
    conn.close()


def test_closed_rows_do_not_conflict_with_open_cycle(fresh_unit_db):
    """Закрытые ряды не попадают в частичный индекс; после closed снова можно создать active."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    _close_all_open_cycles(conn)
    c1 = srv._ensure_active_cycle(conn)
    conn.commit()
    # closed-ряды не конфликтуют с открытым циклом — сколько угодно
    for i in range(3):
        conn.execute(
            "INSERT INTO vein_cycles (cycle_id, started_at, tag1, state, spread_threshold) "
            "VALUES (?, ?, ?, 'closed', 20)",
            (f"vc:closed-{i}", srv._now_iso(), c1["tag1"]),
        )
    conn.commit()
    # закрываем активный — и новый active создаётся свободно
    conn.execute(
        "UPDATE vein_cycles SET state='closed', ended_at=? WHERE cycle_id=?",
        (srv._now_iso(), c1["cycle_id"]),
    )
    c2 = srv._ensure_active_cycle(conn)
    conn.commit()
    assert c2["cycle_id"] != c1["cycle_id"]
    assert c2["state"] == "active"
    conn.close()


def test_ensure_active_cycle_race_returns_winner(fresh_unit_db, monkeypatch):
    """Гонка: конкурент вставил открытый цикл между SELECT и INSERT —
    _ensure_active_cycle ловит IntegrityError и возвращает ряд победителя
    (тот же shape, что у обычного возврата), без исключения."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    _close_all_open_cycles(conn)
    real_pick = srv._cycle_pick

    def racing_pick(c, exclude=None):
        # после пустого SELECT и до нашего INSERT другой запрос успевает
        # создать (и закоммитить) открытый цикл
        other = sqlite3.connect(srv.DB_PATH)
        other.row_factory = sqlite3.Row
        other.execute(
            "INSERT INTO vein_cycles (cycle_id, started_at, tag1, state, spread_threshold) "
            "VALUES (?, ?, ?, 'active', 20)",
            ("vc:race-winner", srv._now_iso(), "iron"),
        )
        other.commit()
        other.close()
        return real_pick(c, exclude=exclude)

    monkeypatch.setattr(srv, "_cycle_pick", racing_pick)
    cycle = srv._ensure_active_cycle(conn)
    assert cycle["cycle_id"] == "vc:race-winner"
    # dict-та же форма, что у нормального возврата (SELECT * → dict(row))
    assert set(cycle.keys()) == {
        "cycle_id", "started_at", "ended_at", "spread_at", "tag1", "tag2",
        "state", "spread_threshold", "world_finds",
    }
    assert cycle["state"] == "active"
    # и повторный вызов идемпотентен — возвращает того же победителя
    again = srv._ensure_active_cycle(conn)
    assert again["cycle_id"] == "vc:race-winner"
    conn.close()
