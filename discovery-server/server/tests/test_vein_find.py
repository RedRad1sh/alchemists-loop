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


# ---------------------------------------------------------------------------
# POST /api/vein/find (Task 7)
# ---------------------------------------------------------------------------

def _seed_recipe_and_element(conn, pair_key="salt|water", out_tag="fire"):
    """Insert a recipe + element so pair is 'known' to server.

    Schema notes (schema.sql): elements requires slug/name/color/layer/
    category NOT NULL (tag has a default, passed explicitly here); recipes
    requires pair_key/a/b/out_id NOT NULL, a_id/b_id point at seeded
    elements 1/2 (FKs are satisfied — seed.py always creates them).
    """
    conn.execute(
        "INSERT OR IGNORE INTO elements (id, slug, name, color, layer, category, tag) "
        "VALUES (9999, 'test_elem', 'Test Element', '#fff', 1, 'basic', ?)",
        (out_tag,),
    )
    conn.execute(
        "INSERT OR IGNORE INTO recipes (pair_key, a, b, a_id, b_id, out_id, discoverer, discoverer_device, created_at) "
        "VALUES (?, 'salt', 'water', 1, 2, 9999, 'bob', 'dev-bob', datetime('now'))",
        (pair_key,),
    )
    conn.commit()


def test_vein_find_personal_success(fresh_unit_db):
    """POST /api/vein/find registers personal find and scores +1."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    _seed_recipe_and_element(conn, "salt|water", cycle["tag1"])
    conn.close()
    resp = client.post("/api/vein/find", json={
        "device_id": "dev-pf1",
        "pair_key": "salt|water",
        "tag": cycle["tag1"],
        "cycle_id": cycle["cycle_id"],
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["points"] == 1
    assert data["cycle_id"] == cycle["cycle_id"]
    # personal_discoveries should have entry
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        pd = conn.execute(
            "SELECT * FROM personal_discoveries WHERE device_id='dev-pf1' AND pair_key='salt|water'"
        ).fetchone()
        assert pd is not None
        # a vein_hits row was written for the cycle (anti-farm + idempotency basis)
        hit = conn.execute(
            "SELECT 1 FROM vein_hits WHERE device_id='dev-pf1' AND cycle_id=? AND pair_key='salt|water'",
            (cycle["cycle_id"],),
        ).fetchone()
        assert hit is not None
    finally:
        conn.close()


def test_vein_find_tag_mismatch(fresh_unit_db):
    """Tag doesn't match element's actual tag → tag_mismatch error."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    _seed_recipe_and_element(conn, "salt|water", cycle["tag1"])
    conn.close()
    resp = client.post("/api/vein/find", json={
        "device_id": "dev-pf2",
        "pair_key": "salt|water",
        "tag": "wrong_tag",
        "cycle_id": cycle["cycle_id"],
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is False
    assert data.get("error") == "tag_mismatch"
    # nothing scored, nothing registered
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        pd = conn.execute(
            "SELECT 1 FROM personal_discoveries WHERE device_id='dev-pf2'"
        ).fetchone()
        assert pd is None
        hit = conn.execute(
            "SELECT 1 FROM vein_hits WHERE device_id='dev-pf2'"
        ).fetchone()
        assert hit is None
    finally:
        conn.close()


def test_vein_find_unknown_pair(fresh_unit_db):
    """Pair absent from recipes → unknown_pair error."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    conn.close()
    resp = client.post("/api/vein/find", json={
        "device_id": "dev-pf5",
        "pair_key": "ghost|nothing",
        "tag": cycle["tag1"],
        "cycle_id": cycle["cycle_id"],
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is False
    assert data.get("error") == "unknown_pair"


def test_vein_find_cycle_mismatch(fresh_unit_db):
    """cycle_id doesn't match current active/spread → cycle_mismatch error."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    _seed_recipe_and_element(conn, "salt|water", cycle["tag1"])
    conn.close()
    resp = client.post("/api/vein/find", json={
        "device_id": "dev-pf3",
        "pair_key": "salt|water",
        "tag": cycle["tag1"],
        "cycle_id": "vc:nonexistent",
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is False
    assert data.get("error") == "cycle_mismatch"


def test_vein_find_idempotent(fresh_unit_db):
    """Same request twice returns same result without double scoring."""
    from fastapi.testclient import TestClient
    srv.init_db()
    client = TestClient(srv.app)
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    _seed_recipe_and_element(conn, "salt|water", cycle["tag1"])
    conn.close()
    body = {
        "device_id": "dev-pf4",
        "pair_key": "salt|water",
        "tag": cycle["tag1"],
        "cycle_id": cycle["cycle_id"],
    }
    r1 = client.post("/api/vein/find", json=body).json()
    r2 = client.post("/api/vein/find", json=body).json()
    assert r1["ok"] is True
    assert r2["ok"] is True
    assert r1["points"] == r2["points"]
    # Only one entry in personal_discoveries
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        count = conn.execute(
            "SELECT COUNT(*) AS c FROM personal_discoveries WHERE device_id='dev-pf4'"
        ).fetchone()["c"]
        assert count == 1
        # Only one vein_hits row too (no double scoring)
        hits = conn.execute(
            "SELECT COUNT(*) AS c FROM vein_hits WHERE device_id='dev-pf4' AND cycle_id=?",
            (cycle["cycle_id"],),
        ).fetchone()["c"]
        assert hits == 1
        # Day points credited exactly once (+1)
        vp = conn.execute(
            "SELECT COALESCE(SUM(points), 0) AS p FROM vein_points WHERE device_id='dev-pf4'"
        ).fetchone()["p"]
        assert vp == 1
    finally:
        conn.close()
