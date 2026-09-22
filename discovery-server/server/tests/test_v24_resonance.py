"""Резонанс 2.0 (v24): отголоски, вехи, потомки, подмастерья гильдии.

- Чужой повтор твоего вещества → +1 к resonance_count вещества и отголосок
  первооткрывателю (баланс капается на ECHO_CAP, вечный счётчик — нет).
- Свои повторы и вещества без автора не засчитываются.
- Потомки: рецепты других игроков, где моё вещество — родитель (a_id/b_id).
- Подмастерья: раз в сутки детерминированный +1 своему веществу (fallback
  малой аудитории).
"""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import seed  # noqa: E402
import server  # noqa: E402


def _fresh_conn():
    import sqlite3
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    schema_path = os.path.join(_here, "..", "schema.sql")
    conn.executescript(open(schema_path, encoding="utf-8").read())
    seed.seed_db(conn)
    conn.commit()
    return conn


class _FakeLLM:
    def __init__(self, name: str, glyph: str = "fire", description: str = "лор"):
        self.name = name
        self.glyph = glyph
        self.description = description

    def generate(self, a, b, a_name, b_name, pair_key):
        return {
            "combinable": True,
            "name": self.name,
            "glyph": self.glyph,
            "description": self.description,
        }


def _mk(conn, a, b, nick, name):
    """Первооткрытие через _generate_for_pair; вернуть DiscoveryData."""
    kind, disc = server._generate_for_pair(
        conn, a, b, server.canonical_pair_key(a, b), nick, _FakeLLM(name)
    )
    assert kind == "created"
    conn.commit()
    return disc


def _players(conn, *pairs):
    for nick, dev in pairs:
        conn.execute(
            "INSERT INTO players (nick, device_id) VALUES (?, ?)", (nick, dev)
        )
    conn.commit()


class TestCreditResonance:
    def test_repeat_credits_discoverer(self):
        conn = _fresh_conn()
        disc = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"), ("Второй", "dev-b"))
        assert server._credit_resonance(conn, disc.id, "Перво", "Второй") is True
        conn.commit()
        row = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id = 'dev-a'"
        ).fetchone()
        assert (row["balance"], row["total"]) == (1, 1)
        cnt = conn.execute(
            "SELECT resonance_count FROM elements WHERE id = ?", (disc.id,)
        ).fetchone()["resonance_count"]
        assert cnt == 1
        # у повторяющего отголосков нет
        assert conn.execute(
            "SELECT COUNT(*) AS c FROM echoes WHERE device_id = 'dev-b'"
        ).fetchone()["c"] == 0
        conn.close()

    def test_self_repeat_no_credit(self):
        conn = _fresh_conn()
        disc = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"))
        assert server._credit_resonance(conn, disc.id, "Перво", "Перво") is False
        cnt = conn.execute(
            "SELECT resonance_count FROM elements WHERE id = ?", (disc.id,)
        ).fetchone()["resonance_count"]
        assert cnt == 0
        assert conn.execute("SELECT COUNT(*) AS c FROM echoes").fetchone()["c"] == 0
        conn.close()

    def test_no_author_no_credit(self):
        conn = _fresh_conn()
        fire_id = conn.execute("SELECT id FROM elements WHERE slug='fire'").fetchone()["id"]
        assert server._credit_resonance(conn, fire_id, None, "Кто-то") is False
        conn.close()

    def test_balance_capped_total_uncapped(self):
        conn = _fresh_conn()
        disc = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"))
        for _ in range(25):
            server._credit_resonance(conn, disc.id, "Перво", "Второй")
        conn.commit()
        row = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id = 'dev-a'"
        ).fetchone()
        assert row["balance"] == server.ECHO_CAP == 20
        assert row["total"] == 25
        conn.close()

    def test_linked_pair_credits_author(self):
        """Новая пара, давшая чужое вещество (reused), — тоже повтор для автора."""
        conn = _fresh_conn()
        disc = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"))
        kind, linked = server._generate_for_pair(
            conn, "sand", "mist", server.canonical_pair_key("sand", "mist"),
            "Второй", _FakeLLM("Звенигород"),
        )
        assert kind == "created" and linked.reused is True
        conn.commit()
        row = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id = 'dev-a'"
        ).fetchone()
        assert (row["balance"], row["total"]) == (1, 1)
        cnt = conn.execute(
            "SELECT resonance_count FROM elements WHERE id = ?", (disc.id,)
        ).fetchone()["resonance_count"]
        assert cnt == 1
        conn.close()


class TestClaim:
    def test_claim_pays_and_resets_balance(self):
        conn = _fresh_conn()
        disc = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"))
        for _ in range(3):
            server._credit_resonance(conn, disc.id, "Перво", "Второй")
        claimed, ether, total = server._claim_echoes(conn, "dev-a")
        assert (claimed, ether, total) == (3, 15, 3)
        row = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id = 'dev-a'"
        ).fetchone()
        assert (row["balance"], row["total"]) == (0, 3)  # вечный счётчик цел
        claimed2, ether2, total2 = server._claim_echoes(conn, "dev-a")
        assert (claimed2, ether2, total2) == (0, 0, 3)
        conn.close()


class TestDescendants:
    def test_only_others_children_count(self):
        conn = _fresh_conn()
        x = _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _mk(conn, x.slug, "fire", "Второй", "ДитяЭха")       # чужой потомок
        _mk(conn, x.slug, "water", "Перво", "СвояВарка")     # свой — не потомок
        desc, total = server._descendants_for(conn, "Перво")
        assert total == 1
        assert len(desc) == 1
        assert desc[0]["name"] == "ДитяЭха" and desc[0]["by"] == "Второй"
        assert desc[0]["slug"] != ""
        # у игрока без открытий потомков нет
        assert server._descendants_for(conn, "Никто") == ([], 0)
        assert server._descendants_for(conn, "") == ([], 0)
        conn.close()


class TestApprentice:
    def test_grant_once_per_day(self):
        conn = _fresh_conn()
        _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _players(conn, ("Перво", "dev-a"))
        grant = server._apprentice_grant(conn, "dev-a", "Перво")
        assert grant == {"name": "Звенигород", "slug": grant["slug"]}
        row = conn.execute(
            "SELECT balance, total, last_apprentice_day FROM echoes WHERE device_id='dev-a'"
        ).fetchone()
        assert (row["balance"], row["total"]) == (1, 1)
        assert row["last_apprentice_day"] == server._today()
        # повторный грант в тот же день — тихо нет
        assert server._apprentice_grant(conn, "dev-a", "Перво") is None
        row2 = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id='dev-a'"
        ).fetchone()
        assert (row2["balance"], row2["total"]) == (1, 1)
        conn.close()

    def test_no_authorship_no_grant(self):
        conn = _fresh_conn()
        _players(conn, ("Пустой", "dev-empty"))
        assert server._apprentice_grant(conn, "dev-empty", "Пустой") is None
        assert server._apprentice_grant(conn, "dev-x", "") is None
        conn.close()

    def test_pick_is_deterministic(self):
        conn = _fresh_conn()
        _mk(conn, "stone", "plant", "Перво", "Звенигород")
        _mk(conn, "sand", "mist", "Перво", "Гудрон")
        _players(conn, ("Перво", "dev-a"))
        mine = conn.execute(
            "SELECT name FROM elements WHERE author='Перво' ORDER BY id"
        ).fetchall()
        expect = mine[
            server._hash_to_int("apprentice_" + server._today() + "_dev-a", len(mine))
        ]["name"]
        grant = server._apprentice_grant(conn, "dev-a", "Перво")
        assert grant["name"] == expect
        conn.close()


class _FakeSeq:
    """LLM-заглушка с очередью имён (без цифр — иначе модель сочтёт отказом)."""

    def __init__(self, names):
        self.names = list(names)

    def generate(self, *a, **k):
        name = self.names.pop(0) if self.names else "Очередной"
        return {"combinable": True, "name": name, "glyph": "fire", "description": "л"}


def _client_for(tmp_path, monkeypatch, fake):
    from fastapi.testclient import TestClient
    sys.path.insert(0, os.path.join(_here, ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "res.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: fake)
    return TestClient(srv.app)


class TestEchoesHttp:
    def test_repeat_claim_flow(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch, _FakeSeq(["Резонит"]))
        with c:
            r1 = c.post("/api/discover", json={
                "a": "stone", "b": "plant", "nick": "РезА", "device_id": "res-a"})
            assert r1.status_code == 200 and r1.json()["status"] == "created"
            # чужой повтор через brew-check (именно так клиент узнаёт известное)
            rb = c.post("/api/brew-check", json={
                "a": "stone", "b": "plant", "nick": "РезБ", "device_id": "res-b"})
            assert rb.json()["status"] == "known"
            g = c.get("/api/echoes", params={"device_id": "res-a"}).json()
            assert g["ok"] is True and g["nick"] == "РезА"
            # 1 повтор + 1 подмастерье (первый запрос дня)
            assert g["balance"] == 2 and g["total"] == 2
            assert g["cap"] == 20 and g["echo_ether"] == 5
            assert g["apprentice"] and g["apprentice"]["name"] == "Резонит"
            assert g["top"][0]["count"] == 2
            assert g["milestones"] == {"m10": False, "m50": False, "m100": False}
            cl = c.post("/api/echoes/claim", json={"device_id": "res-a"}).json()
            assert (cl["claimed"], cl["ether"], cl["total"]) == (2, 10, 2)
            g2 = c.get("/api/echoes", params={"device_id": "res-a"}).json()
            assert (g2["balance"], g2["total"]) == (0, 2)
            assert g2["apprentice"] is None  # подмастерье уже отметился

    def test_descendants_over_http(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch, _FakeSeq(["Резонит", "ДитяЭха"]))
        with c:
            r1 = c.post("/api/discover", json={
                "a": "stone", "b": "plant", "nick": "РезА", "device_id": "res-a"})
            x_slug = r1.json()["discovery"]["slug"]
            r2 = c.post("/api/discover", json={
                "a": x_slug, "b": "fire", "nick": "РезБ", "device_id": "res-b"})
            assert r2.json()["status"] == "created"
            g = c.get("/api/echoes", params={"device_id": "res-a"}).json()
            assert g["descendants_total"] == 1
            assert g["descendants"][0]["name"] == "ДитяЭха"
            assert g["descendants"][0]["by"] == "РезБ"

    def test_unknown_device_is_empty(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch, _FakeSeq([]))
        with c:
            g = c.get("/api/echoes", params={"device_id": "nope"}).json()
            assert g["ok"] is True and g["balance"] == 0 and g["total"] == 0
            assert g["descendants"] == [] and g["top"] == []
            cl = c.post("/api/echoes/claim", json={"device_id": "nope"}).json()
            assert (cl["claimed"], cl["ether"]) == (0, 0)


class TestResonanceMigration:
    """Старая БД без resonance_count/echoes: init_db доводит схему без падений."""

    OLD_SCHEMA = """
    CREATE TABLE elements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        color TEXT NOT NULL,
        layer INTEGER NOT NULL,
        category TEXT NOT NULL,
        glyph TEXT NOT NULL DEFAULT '',
        d TEXT NOT NULL DEFAULT '',
        author TEXT,
        created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pair_key TEXT NOT NULL UNIQUE,
        a TEXT NOT NULL, b TEXT NOT NULL,
        a_id INTEGER, b_id INTEGER, out_id INTEGER NOT NULL,
        discoverer TEXT,
        created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE players (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nick TEXT NOT NULL,
        device_id TEXT NOT NULL UNIQUE,
        created_at TEXT DEFAULT (datetime('now'))
    );
    """

    def test_old_db_gets_resonance(self, tmp_path):
        import sqlite3
        import subprocess

        db = str(tmp_path / "oldres.sqlite")
        conn = sqlite3.connect(db)
        conn.executescript(self.OLD_SCHEMA)
        conn.execute(
            "INSERT INTO elements(slug,name,color,layer,category) "
            "VALUES ('fire','Огонь','#ff8c42',1,'fire')"
        )
        conn.commit()
        conn.close()

        code = (
            "import sqlite3, os, sys\n"
            f"os.environ['ALCHEMY_DB_PATH'] = {db!r}\n"
            f"sys.path.insert(0, {os.path.join(_here, '..')!r})\n"
            "import server\n"
            "server.init_db()\n"
            "conn = sqlite3.connect(os.environ['ALCHEMY_DB_PATH'])\n"
            "conn.row_factory = sqlite3.Row\n"
            "cols = {r['name'] for r in conn.execute('PRAGMA table_info(elements)')}\n"
            "assert 'resonance_count' in cols, cols\n"
            "tabs = {r['name'] for r in conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")}\n"
            "assert 'echoes' in tabs, tabs\n"
            "cnt = conn.execute('SELECT resonance_count FROM elements WHERE slug=\\'fire\\'').fetchone()[0]\n"
            "assert cnt == 0, cnt\n"
            "print('RESONANCE_MIGRATION_OK')\n"
        )
        r = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=60
        )
        assert r.returncode == 0, "stderr: %s\nstdout: %s" % (r.stderr, r.stdout)
        assert "RESONANCE_MIGRATION_OK" in r.stdout
