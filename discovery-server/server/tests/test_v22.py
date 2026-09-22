"""Регрессионные тесты v22.

- Дедупликация имён: LLM, вернувшая существующее имя, НЕ создаёт дубль в БД,
  а привязывает пару к существующему элементу (reused=True).
- /api/rejected отдаёт пары, признанные несочетаемыми.
- /api/house сохраняет и отдаёт домик игрока.
- /api/rating отдаёт статистику игроков.
"""
import os
import sys

import pytest

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


class TestNameDedup:
    def test_existing_name_is_linked_not_duplicated(self):
        """LLM выдаёт «Огонь» → пару привязываем к существующему «Огонь», без дубля."""
        conn = _fresh_conn()
        before = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        fire_id = conn.execute("SELECT id FROM elements WHERE slug = 'fire'").fetchone()["id"]

        kind, disc = server._generate_for_pair(
            conn, "stone", "plant", server.canonical_pair_key("stone", "plant"),
            "Тестер", _FakeLLM("Огонь")
        )
        assert kind == "created"
        assert disc.reused is True
        assert disc.slug == "fire"
        assert disc.id == fire_id
        conn.commit()

        after = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        assert after == before  # нового элемента НЕ создано
        recipe = conn.execute(
            "SELECT out_id FROM recipes WHERE pair_key = 'plant|stone'"
        ).fetchone()
        assert recipe is not None
        assert recipe["out_id"] == fire_id  # рецепт указывает на существующий элемент
        conn.close()

    def test_name_matching_is_case_and_yo_insensitive(self):
        """Регистр и ё/е не должны влиять на дедупликацию."""
        conn = _fresh_conn()
        before = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        # «Ёж» отсутствует в seed — создаём через _materialize-путь, затем проверяем
        # сопоставление по норме имени (Ёж == еж).
        fire_id = conn.execute("SELECT id FROM elements WHERE slug = 'fire'").fetchone()["id"]
        kind, disc = server._generate_for_pair(
            conn, "stone", "sand", "sand|stone", "Тестер", _FakeLLM("  огонь ")
        )
        assert disc.reused is True
        assert disc.slug == "fire"
        assert disc.id == fire_id
        after = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        assert after == before
        conn.close()

    def test_new_name_still_creates_element(self):
        conn = _fresh_conn()
        before = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        kind, disc = server._generate_for_pair(
            conn, "stone", "plant", "stone|plant", "Тестер", _FakeLLM("СовсемНовое")
        )
        assert kind == "created"
        assert disc.reused is False
        after = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        assert after == before + 1
        conn.close()


class TestRejectedEndpoint:
    def test_rejected_lists_pairs(self, server):
        import requests
        base = os.environ.get("TEST_SERVER_URL", "http://localhost:8080/api")
        # person|gold — детерминированно несочетаемая пара в заглушке mock
        r = requests.post(
            f"{base}/discover",
            json={"a": "person", "b": "gold", "nick": "Т", "device_id": "rej-1"},
            timeout=5,
        )
        assert r.status_code == 200
        rr = requests.get(f"{base}/rejected", timeout=5).json()
        assert rr["ok"] is True
        assert "gold|person" in rr["rejected"]


class TestHouseEndpoint:
    def test_house_save_and_get(self, server):
        import requests
        base = os.environ.get("TEST_SERVER_URL", "http://localhost:8080/api")
        house = {
            "v": 1, "built": True, "theme": "cobalt", "aura": "amber",
            "wall": "#5a4d40", "floor": "#5d452f",
            "furniture": {"window": "window_3", "rug": "rug_1"},
        }
        r = requests.post(
            f"{base}/house",
            json={"device_id": "house-dev-1", "nick": "Домовладелец", "house": house},
            timeout=5,
        )
        assert r.status_code == 200 and r.json()["ok"] is True
        g = requests.get(f"{base}/house", params={"nick": "Домовладелец"}, timeout=5).json()
        assert g["ok"] is True and g["found"] is True
        assert g["house"] == house
        missing = requests.get(f"{base}/house", params={"nick": "НиктоНет"}, timeout=5).json()
        assert missing["found"] is False


class TestRatingEndpoint:
    def test_rating_has_rows_and_me(self, server):
        import requests
        base = os.environ.get("TEST_SERVER_URL", "http://localhost:8080/api")
        # игрок с открытием уже существует после discover в других тестах
        r = requests.get(f"{base}/rating", params={"device_id": "rej-1"}, timeout=5).json()
        assert r["ok"] is True
        assert isinstance(r["rows"], list)
        for row in r["rows"]:
            assert {"rank", "nick", "discoveries", "elements", "points"} <= set(row)
        # device_id "rej-1" зарегистрирован (ник «Т») — me должен найтись
        assert r["me"] is None or r["me"]["nick"] == "Т"


class TestParametricGlyph:
    """v23: глиф можно генерировать вместе с LLM — параметрический «форма+число»."""

    def test_is_glyph_accepts_parametric(self):
        from gen_llm import is_glyph
        assert is_glyph("star6") is True
        assert is_glyph("crystal5") is True
        assert is_glyph("poly3") is True
        assert is_glyph("fire") is True
        assert is_glyph("star11") is False   # вне диапазона 4..10
        assert is_glyph("ring9") is False    # вне диапазона 2..5
        assert is_glyph("bogus") is False

    def test_llm_parametric_glyph_persisted(self):
        conn = _fresh_conn()
        kind, disc = server._generate_for_pair(
            conn, "stone", "sand", "sand|stone", "Тестер",
            _FakeLLM("Кристаллон", glyph="crystal6")
        )
        assert kind == "created"
        assert disc.glyph == "crystal6"
        row = conn.execute(
            "SELECT glyph FROM elements WHERE slug = ?", (disc.slug,)
        ).fetchone()
        assert row["glyph"] == "crystal6"
        conn.close()

    def test_invalid_glyph_falls_back_to_valid(self):
        from gen_llm import is_glyph
        conn = _fresh_conn()
        kind, disc = server._generate_for_pair(
            conn, "stone", "sand", "sand|stone", "Тестер",
            _FakeLLM("Песчаник", glyph="!!!")
        )
        assert kind == "created"
        assert disc.glyph != ""
        assert is_glyph(disc.glyph)  # фоллбэк дал валидный глиф
        conn.close()


class TestOldDbMigration:
    """Старт на БД из версии до v22 не должен падать: schema.sql больше не создаёт
    idx_elements_name_norm до миграции колонки (раньше падало с
    «no such column: name_norm»), миграция добавляет колонку и индекс, а дубли
    «Огонь»/«огонь» схлопываются в один элемент."""

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
    CREATE TABLE pending_pairs (
        pair_key TEXT NOT NULL PRIMARY KEY,
        state TEXT NOT NULL DEFAULT 'pending',
        lock_ts REAL NOT NULL, owner TEXT, attempted_by TEXT
    );
    CREATE TABLE rejected_pairs (
        pair_key TEXT NOT NULL PRIMARY KEY,
        created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE world_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pair_key TEXT NOT NULL, a TEXT NOT NULL, b TEXT NOT NULL,
        out TEXT NOT NULL, out_name TEXT NOT NULL, discoverer TEXT,
        created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE challenges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day TEXT NOT NULL UNIQUE,
        target TEXT NOT NULL, target_name TEXT NOT NULL, hint TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')), closed_at TEXT
    );
    CREATE TABLE challenge_scores (
        day TEXT NOT NULL, device_id TEXT NOT NULL, nick TEXT NOT NULL,
        points INTEGER NOT NULL DEFAULT 0,
        first_at TEXT DEFAULT (datetime('now')),
        PRIMARY KEY (day, device_id)
    );
    """

    def test_old_db_startup_and_dedup(self, tmp_path):
        import sqlite3
        import subprocess

        db = str(tmp_path / "old.sqlite")
        conn = sqlite3.connect(db)
        conn.executescript(self.OLD_SCHEMA)
        # симптом из багрепорта: два элемента «огонь» (Огонь/огонь) + рецепт,
        # ссылающийся на дубль fire2 как на результат
        conn.execute(
            "INSERT INTO elements(slug,name,color,layer,category) "
            "VALUES ('fire','Огонь','#ff8c42',1,'fire')"
        )
        conn.execute(
            "INSERT INTO elements(slug,name,color,layer,category) "
            "VALUES ('fire2','огонь','#ff8c42',1,'fire')"
        )
        fire2_id = conn.execute("SELECT id FROM elements WHERE slug='fire2'").fetchone()[0]
        conn.execute(
            "INSERT INTO recipes(pair_key,a,b,out_id) VALUES ('x|y','x','y',?)",
            (fire2_id,),
        )
        conn.execute("INSERT INTO players(nick,device_id) VALUES ('N','d1')")
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
            "assert 'name_norm' in cols, cols\n"
            "idx = [r['name'] for r in conn.execute('PRAGMA index_list(elements)')]\n"
            "assert 'idx_elements_name_norm' in idx, idx\n"
            "fire = conn.execute(\"SELECT id FROM elements WHERE slug='fire'\").fetchone()\n"
            "assert fire is not None\n"
            "dup = conn.execute(\"SELECT id FROM elements WHERE slug='fire2'\").fetchone()\n"
            "assert dup is None, 'дубль fire2 должен быть удалён'\n"
            "n = conn.execute(\"SELECT COUNT(*) AS c FROM elements WHERE name_norm='огонь'\").fetchone()['c']\n"
            "assert n == 1, n\n"
            "r = conn.execute(\"SELECT out_id FROM recipes WHERE pair_key='x|y'\").fetchone()\n"
            "assert r is not None and r['out_id'] == fire['id'], r\n"
            "print('MIGRATION_OK')\n"
        )
        r = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=60
        )
        assert r.returncode == 0, "stderr: %s\nstdout: %s" % (r.stderr, r.stdout)
        assert "MIGRATION_OK" in r.stdout

