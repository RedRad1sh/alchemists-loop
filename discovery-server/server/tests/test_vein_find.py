import sqlite3
import server as srv


def _setup_cycle(conn):
    """Helper: create an active cycle with known tag."""
    cycle = srv._ensure_active_cycle(conn)
    return cycle


def test_score_vein_cycle_world_first(fresh_unit_db):
    """World-first with matching tag: +2 points, guaranteed streak."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = _setup_cycle(conn)
    result = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|water", "dev1", "alice",
        is_world_first=True,
    )
    assert result is not None
    assert result["points"] == 2
    assert result["streak_added"] is True
    assert result["streak_count"] == 1
    assert result["cap_reached"] is False
    conn.close()


def test_score_vein_cycle_wrong_tag(fresh_unit_db):
    """Tag not in {tag1, tag2}: returns None."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = _setup_cycle(conn)
    result = srv._score_vein_cycle(
        conn, cycle, "nonexistent_tag", "fire|water", "dev1", "alice",
        is_world_first=True,
    )
    assert result is None
    conn.close()


def test_score_vein_cycle_anti_farm(fresh_unit_db):
    """Same pair twice in same cycle: second call returns None."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = _setup_cycle(conn)
    r1 = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|water", "dev1", "alice",
        is_world_first=True,
    )
    assert r1 is not None
    r2 = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|water", "dev1", "alice",
        is_world_first=False,
    )
    assert r2 is None
    conn.close()


def test_score_vein_cycle_personal_find(fresh_unit_db):
    """Personal find: +1 point, 10% streak roll (forced via seed)."""
    import random
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = _setup_cycle(conn)
    random.seed(0)  # deterministic roll
    result = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "salt|water", "dev1", "alice",
        is_world_first=False,
    )
    assert result is not None
    assert result["points"] == 1
    # streak_added depends on random seed; just check structure
    assert "streak_added" in result
    assert "streak_count" in result
    conn.close()


def test_score_vein_cycle_cap_claimed_prevents_roll(fresh_unit_db):
    """After cap_claimed, no more streak rolls even if count resets."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = _setup_cycle(conn)
    # Manually set cap_claimed
    conn.execute(
        "INSERT INTO vein_streaks (device_id, cycle_id, count, cap_claimed) VALUES (?, ?, 0, 1)",
        ("dev1", cycle["cycle_id"]),
    )
    conn.commit()
    result = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|earth", "dev1", "alice",
        is_world_first=True,
    )
    assert result is not None
    assert result["streak_added"] is False
    assert result["cap_reached"] is False
    conn.close()


class _CycleTagGen:
    """Fake LLM generator emitting a fixed (cycle) tag → created-branch."""

    def __init__(self, tag):
        self.tag = tag

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        return {"combinable": True, "name": "Циклолит", "glyph": "mist",
                "description": "Рождено циклом.", "tag": self.tag}


def test_discover_world_first_uses_cycle_scorer(tmp_path, monkeypatch):
    """POST /api/discover created-branch scores via _score_vein_cycle:
    vein field has the new shape and vein_hits row carries cycle_id."""
    from fastapi.testclient import TestClient
    db = str(tmp_path / "wf.db")
    monkeypatch.setattr(srv, "DB_PATH", db)
    srv.init_db()
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    conn.commit()
    conn.close()

    monkeypatch.setattr(srv, "get_llm", lambda: _CycleTagGen(cycle["tag1"]))
    client = TestClient(srv.app)
    resp = client.post("/api/discover", json={
        "a": "mud", "b": "stone", "nick": "tester", "device_id": "dev-wf1",
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "created"
    assert data["discovery"]["reused"] is False

    vein = data["vein"]
    assert vein is not None
    # world-first roll: +2 points, streak guaranteed, cap far away
    assert vein["points"] == 2
    assert vein["streak_added"] is True
    assert vein["streak_count"] == 1
    assert vein["cap_reached"] is False

    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    try:
        pair_key = srv.canonical_pair_key("mud", "stone")
        hit = conn.execute(
            "SELECT * FROM vein_hits WHERE device_id='dev-wf1' "
            "AND cycle_id=? AND pair_key=?",
            (cycle["cycle_id"], pair_key),
        ).fetchone()
        assert hit is not None
        # world-first increments cycle world_finds
        wf = conn.execute(
            "SELECT world_finds FROM vein_cycles WHERE cycle_id=?",
            (cycle["cycle_id"],),
        ).fetchone()["world_finds"]
        assert wf == 1
        # legacy weekly counter is NOT written by /discover anymore
        legacy = conn.execute("SELECT COUNT(*) AS c FROM legacy_vein_hits").fetchone()["c"]
        assert legacy == 0
    finally:
        conn.close()
