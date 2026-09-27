"""Недельный слой (v30): теги, туманная жила, ярмарка гильдии."""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import seed  # noqa: E402
import server as srv  # noqa: E402
from gen_llm import TAGS  # noqa: E402


def _fresh_conn():
    import sqlite3
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    schema_path = os.path.join(_here, "..", "schema.sql")
    conn.executescript(open(schema_path, encoding="utf-8").read())
    seed.seed_db(conn)
    conn.commit()
    return conn


def _client_for(tmp_path, monkeypatch, fake_llm=None):
    from fastapi.testclient import TestClient
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "week.db"))
    if fake_llm is not None:
        monkeypatch.setattr(srv, "get_llm", lambda: fake_llm)
    return TestClient(srv.app)


class _FakeGen:
    """Генератор с заданным именем и тегом."""
    def __init__(self, name="Туманник", tag="трава"):
        self.name = name
        self.tag = tag

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        return {"combinable": True, "name": self.name, "glyph": "mist",
                "description": "Рождено туманом.", "tag": self.tag}


class TestTags:
    def test_seed_tags_cover_vocab(self):
        conn = _fresh_conn()
        rows = conn.execute("SELECT slug, tag FROM elements").fetchall()
        assert len(rows) == 57
        assert all(r["tag"] in TAGS for r in rows)
        by_slug = {r["slug"]: r["tag"] for r in rows}
        assert by_slug["fire"] == "огонь" and by_slug["gold"] == "металл"
        assert by_slug["ice"] == "лёд" and by_slug["sun"] == "свет"
        assert len(set(by_slug.values())) == 12  # весь словарь в ходу
        conn.close()

    def test_llm_tag_passthrough(self, tmp_path, monkeypatch):
        import sqlite3
        c = _client_for(tmp_path, monkeypatch, _FakeGen("Моховик", "трава"))
        with c:
            r = c.post("/api/discover", json={
                "a": "mud", "b": "stone", "nick": "Таг",
                "device_id": "dev-tag"}).json()
            assert r["status"] == "created"
            assert r["discovery"]["tag"] == "трава"
            row = sqlite3.connect(str(tmp_path / "week.db")).execute(
                "SELECT tag FROM elements WHERE slug = ?", (r["discovery"]["slug"],)).fetchone()
            assert row[0] == "трава"

    def test_tag_fallback_category(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch, _FakeGen("Безтег", "не-тег"))
        with c:
            r = c.post("/api/discover", json={
                "a": "mud", "b": "stone", "nick": "Таг",
                "device_id": "dev-tag2"}).json()
            assert r["status"] == "created"
            # мусорный тег → категория родителей (земля)
            assert r["discovery"]["tag"] == "земля"

    def test_old_db_gets_tag(self, tmp_path):
        import sqlite3
        db = str(tmp_path / "oldtag.sqlite")
        conn = sqlite3.connect(db)
        conn.execute(
            "CREATE TABLE elements (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL, color TEXT NOT NULL, "
            "layer INTEGER NOT NULL, category TEXT NOT NULL, author TEXT)"
        )
        conn.execute("INSERT INTO elements (slug, name, color, layer, category) VALUES "
                     "('fire', 'Огонь', '#fff', 0, 'огонь')")
        conn.execute(
            "CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "nick TEXT NOT NULL, device_id TEXT NOT NULL UNIQUE)"
        )
        conn.commit()
        conn.close()
        old = srv.DB_PATH
        srv.DB_PATH = db
        try:
            srv.init_db()
        finally:
            srv.DB_PATH = old
        conn = sqlite3.connect(db)
        cols = {r[1] for r in conn.execute("PRAGMA table_info(elements)").fetchall()}
        assert "tag" in cols
        assert conn.execute("SELECT tag FROM elements WHERE slug='fire'").fetchone()[0] == "огонь"
        pcols = {r[1] for r in conn.execute("PRAGMA table_info(players)").fetchall()}
        assert "last_seen" in pcols
        conn.close()


class TestVein:
    def test_pick_deterministic(self):
        conn = _fresh_conn()
        a = srv._vein_state(conn, "2026-W37")
        b = srv._vein_state(conn, "2026-W37")
        assert a == b and a[0] in TAGS and a[1] in TAGS
        conn.close()

    def test_spread_when_empty(self):
        from datetime import date
        conn = _fresh_conn()
        # сидовые рецепты без discoverer — находок недели нет
        assert srv._vein_state(conn, "2026-W37", date(2026, 9, 12))[2] is True  # суббота
        assert srv._vein_state(conn, "2026-W37", date(2026, 9, 7))[2] is False  # понедельник
        conn.close()

    def test_discover_vein_bonus(self, tmp_path, monkeypatch):
        import sqlite3
        c = _client_for(tmp_path, monkeypatch)
        with c:
            # T6: /discover скорит жилу по АКТИВНОМУ ЦИКЛУ, не по неделе
            db = sqlite3.connect(str(tmp_path / "week.db"))
            db.row_factory = sqlite3.Row
            cycle = srv._ensure_active_cycle(db)
            db.commit()
            # подменяем генератор под тег цикла
            monkeypatch.setattr(srv, "get_llm", lambda: _FakeGen("Жилистый", cycle["tag1"]))
            r = c.post("/api/discover", json={
                "a": "mud", "b": "stone", "nick": "Жила",
                "device_id": "dev-v"}).json()
            assert r["status"] == "created"
            v = r["vein"]
            assert v is not None and v["points"] == 2
            assert v["streak_added"] is True and v["streak_count"] == 1
            assert v["cap_reached"] is False
            # U6/T05: vein-очки — отдельный канал vein_points (не challenge)
            pts = db.execute(
                "SELECT points FROM vein_points WHERE device_id='dev-v'").fetchone()
            assert pts and pts[0] >= 2
            cs = db.execute(
                "SELECT points FROM challenge_scores WHERE device_id='dev-v'").fetchone()
            assert cs is None or cs[0] < 2  # сюда жила больше не льётся
            # hit привязан к циклу: cycle_id + pair_key в vein_hits
            pk = srv.canonical_pair_key("mud", "stone")
            hit = db.execute(
                "SELECT * FROM vein_hits WHERE device_id='dev-v' AND cycle_id=? AND pair_key=?",
                (cycle["cycle_id"], pk)).fetchone()
            assert hit is not None
            # legacy-неделя /discover больше не пишется (my_hits не растёт)
            assert db.execute(
                "SELECT COUNT(*) FROM legacy_vein_hits").fetchone()[0] == 0
            db.close()

    def test_streak_cap(self, tmp_path, monkeypatch):
        import sqlite3
        c = _client_for(tmp_path, monkeypatch)
        with c:
            st = c.get("/api/week/status", params={"device_id": "dev-s"}).json()
            tag1 = st["vein"]["tag1"]
            monkeypatch.setattr(srv.random, "random", lambda: 0.0)  # прожилка всегда
            db = sqlite3.connect(str(tmp_path / "week.db"))
            db.row_factory = sqlite3.Row
            for _ in range(10):
                srv._score_vein(db, st["week"], tag1, "2026-09-12", "dev-s", "Жила")
            db.commit()
            n = db.execute("SELECT streaks FROM legacy_vein_hits WHERE device_id='dev-s'").fetchone()[0]
            hits = db.execute("SELECT count FROM legacy_vein_hits WHERE device_id='dev-s'").fetchone()[0]
            db.close()
            assert (hits, n) == (10, 5)


class TestFair:
    def _ensure_tag_pairs(self, db_path, tag, n):
        """Гарантированные пары с выходом-тегом (сиды + вставка при нужде)."""
        import sqlite3
        db = sqlite3.connect(db_path)
        db.row_factory = sqlite3.Row
        rows = db.execute(
            "SELECT r.a, r.b FROM recipes r JOIN elements e ON r.out_id = e.id "
            "WHERE e.tag = ?", (tag,)).fetchall()
        pairs = [(r["a"], r["b"]) for r in rows]
        if len(pairs) < n:
            out = db.execute("SELECT id FROM elements WHERE tag = ? LIMIT 1", (tag,)).fetchone()
            a_id = db.execute("SELECT id FROM elements WHERE slug='fire'").fetchone()["id"]
            b_id = db.execute("SELECT id FROM elements WHERE slug='water'").fetchone()["id"]
            for i in range(n - len(pairs)):
                a, b = f"fair-a-{tag}-{i}", f"fair-b-{tag}-{i}"
                key = "|".join(sorted([a, b]))
                db.execute(
                    "INSERT OR IGNORE INTO recipes (pair_key, a, b, a_id, b_id, out_id)"
                    " VALUES (?,?,?,?,?,?)",
                    (key, a, b, a_id, b_id, out["id"]))
                pairs.append((a, b))
            db.commit()
        db.close()
        return pairs[:n]

    def test_ensure_goal_min(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch)
        with c:
            st = c.get("/api/week/status", params={"device_id": "dev-f"}).json()
            assert st["ok"] is True and st["fair"]["goal"] >= 10
            assert st["fair"]["tag"] in TAGS

    def test_brew_distinct_pairs(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch)
        with c:
            st = c.get("/api/week/status", params={"device_id": "dev-f"}).json()
            tag = st["fair"]["tag"]
            (a, b), _other = self._ensure_tag_pairs(str(tmp_path / "week.db"), tag, 2)
            r1 = c.post("/api/fair/brew", json={"device_id": "dev-f", "a": a, "b": b}).json()
            assert r1["counted"] is True and r1["contrib"] == 1
            r2 = c.post("/api/fair/brew", json={"device_id": "dev-f", "a": b, "b": a}).json()
            assert r2["counted"] is False and r2["contrib"] == 1  # та же пара
            r3 = c.post("/api/fair/brew", json={
                "device_id": "dev-f", "a": "не-пара", "b": "вообще"}).json()
            assert r3["counted"] is False  # неизвестной пары нет в recipes

    def test_claim_regen_and_double(self, tmp_path, monkeypatch):
        import sqlite3
        c = _client_for(tmp_path, monkeypatch)
        with c:
            st = c.get("/api/week/status", params={"device_id": "dev-c"}).json()
            week, tag, goal = st["week"], st["fair"]["tag"], st["fair"]["goal"]
            pairs = self._ensure_tag_pairs(str(tmp_path / "week.db"), tag, 3)
            for a, b in pairs:
                c.post("/api/fair/brew", json={"device_id": "dev-c", "a": a, "b": b})
            # закрываем котёл вручную (прогресс + подмастерья)
            db = sqlite3.connect(str(tmp_path / "week.db"))
            db.execute("UPDATE fair_weeks SET progress = ? WHERE week = ?", (goal, week))
            db.commit()
            db.close()
            g1 = c.post("/api/fair/claim", json={"device_id": "dev-c"}).json()
            assert {"week": week, "kind": "regen", "amount": 0} in g1["grants"]
            g2 = c.post("/api/fair/claim", json={"device_id": "dev-c"}).json()
            assert g2["grants"] == []  # повторный забор пуст

    def test_claim_consolation_open_pot(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch)
        with c:
            st = c.get("/api/week/status", params={"device_id": "dev-e"}).json()
            tag = st["fair"]["tag"]
            (a, b), = self._ensure_tag_pairs(str(tmp_path / "week.db"), tag, 1)
            c.post("/api/fair/brew", json={"device_id": "dev-e", "a": a, "b": b})
            # котёл не закрыт → текущей неделе гранта нет
            g = c.post("/api/fair/claim", json={"device_id": "dev-e"}).json()
            assert g["grants"] == []
