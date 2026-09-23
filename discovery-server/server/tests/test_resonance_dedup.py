"""T03 (U4): дедуп резонанса — фарм повторяющими варками закрыт.

Инварианты:
- (pair_key, brewer) кредитует резонанс РОВНО ОДИН РАЗ НА ВСЁ ВРЕМЯ (per-life):
  100/1000 повторных варок чужой пары с одного устройства — не более 1 кредита.
- brew-check — читающий путь: экономику НЕ пишет вообще (0 кредитов).
- pair_key обязателен: без ключа кредит не начисляется (fail-closed).
- Свои повторы / отсутствие автора — как раньше: без кредита, причём
  дедуп-слот НЕ расходуется (проверки идут до INSERT).
"""
import os
import sqlite3
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import seed  # noqa: E402
import server  # noqa: E402

PK = "plant|stone"  # canonical_pair_key("stone", "plant")


def _fresh_conn():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    schema_path = os.path.join(_here, "..", "schema.sql")
    conn.executescript(open(schema_path, encoding="utf-8").read())
    seed.seed_db(conn)
    conn.commit()
    return conn


def _mk_element(conn):
    """Чужое вещество «Звенигород» (автор dev-a/Перво) + рецепт stone|plant."""
    cur = conn.execute(
        "INSERT INTO elements (slug, name, name_norm, color, layer, category, "
        "author, author_device, resonance_count) "
        "VALUES ('zven','Звенигород',?,'#fff',2,'stone','Перво','dev-a',0)",
        (seed.norm_name("Звенигород"),),
    )
    conn.execute(
        "INSERT INTO recipes (pair_key, a, b, out_id, discoverer, discoverer_device) "
        "VALUES (?, 'plant', 'stone', ?, 'Перво', 'dev-a')",
        (PK, cur.lastrowid),
    )
    conn.execute("INSERT INTO players (nick, device_id) VALUES ('Перво', 'dev-a')")
    conn.commit()
    return cur.lastrowid


def _echo_total(conn, device):
    row = conn.execute(
        "SELECT total FROM echoes WHERE device_id = ?", (device,)
    ).fetchone()
    return row["total"] if row else 0


def _count(conn):
    return conn.execute(
        "SELECT resonance_count FROM elements WHERE author_device = 'dev-a'"
    ).fetchone()["resonance_count"]


class TestDedupUnit:
    def test_same_pair_same_device_credits_once(self):
        conn = _fresh_conn()
        out_id = _mk_element(conn)
        kw = dict(author_device="dev-a", brewer_device="dev-b", pair_key=PK)
        assert server._credit_resonance(conn, out_id, "Перво", "Второй", **kw) is True
        for _ in range(100):  # фарм повторными варками одной пары
            assert server._credit_resonance(conn, out_id, "Перво", "Второй", **kw) is False
        conn.commit()
        assert _echo_total(conn, "dev-a") == 1
        assert _count(conn) == 1
        conn.close()

    def test_second_device_gets_its_once(self):
        conn = _fresh_conn()
        out_id = _mk_element(conn)
        assert server._credit_resonance(
            conn, out_id, "Перво", "Второй",
            author_device="dev-a", brewer_device="dev-b", pair_key=PK) is True
        assert server._credit_resonance(
            conn, out_id, "Перво", "Третий",
            author_device="dev-a", brewer_device="dev-c", pair_key=PK) is True
        assert server._credit_resonance(
            conn, out_id, "Перво", "Третий",
            author_device="dev-a", brewer_device="dev-c", pair_key=PK) is False
        conn.commit()
        assert _echo_total(conn, "dev-a") == 2  # ровно по одному с устройства
        assert _count(conn) == 2
        conn.close()

    def test_legacy_brewer_without_device_dedups_by_nick(self):
        conn = _fresh_conn()
        out_id = _mk_element(conn)
        kw = dict(author_device="dev-a", brewer_device="", pair_key=PK)
        assert server._credit_resonance(conn, out_id, "Перво", "Второй", **kw) is True
        assert server._credit_resonance(conn, out_id, "Перво", "Второй", **kw) is False
        conn.close()

    def test_missing_pair_key_never_credits(self):
        """Fail-closed: кредит без ключа дедупа невозможен."""
        conn = _fresh_conn()
        out_id = _mk_element(conn)
        assert server._credit_resonance(
            conn, out_id, "Перво", "Второй",
            author_device="dev-a", brewer_device="dev-b") is False
        conn.commit()
        assert _echo_total(conn, "dev-a") == 0
        assert _count(conn) == 0
        assert conn.execute("SELECT COUNT(*) AS c FROM resonance_seen").fetchone()["c"] == 0
        conn.close()

    def test_ineligible_repeat_does_not_consume_slot(self):
        """Свой повтор идёт мимо дедупа: чужой кредит после него жив."""
        conn = _fresh_conn()
        out_id = _mk_element(conn)
        assert server._credit_resonance(
            conn, out_id, "Перво", "Перво",
            author_device="dev-a", brewer_device="dev-a", pair_key=PK) is False
        assert conn.execute("SELECT COUNT(*) AS c FROM resonance_seen").fetchone()["c"] == 0
        assert server._credit_resonance(
            conn, out_id, "Перво", "Второй",
            author_device="dev-a", brewer_device="dev-b", pair_key=PK) is True
        conn.close()


class TestFarmRegressionHttp:
    """Точная проверка из брифа: 100 повторных brew-check одной чужой пары
    с двух устройств -> не более 1 кредита на устройство за период."""

    class _Fake:
        provider = "mock"  # external-LLM budget не тратим на тесты

        def generate(self, a, b, a_name, b_name, pair_key):
            return {"combinable": True, "name": "Дедупит",
                    "glyph": "fire", "description": "тест"}

    def _client(self, tmp_path, monkeypatch):
        from fastapi.testclient import TestClient
        import server as srv
        monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "dedup.db"))
        monkeypatch.setattr(srv, "get_llm", lambda: self._Fake())
        return srv, TestClient(srv.app)

    def test_100_brewchecks_zero_credits(self, tmp_path, monkeypatch):
        srv, c = self._client(tmp_path, monkeypatch)
        with c:
            r = c.post("/api/discover", json={
                "a": "stone", "b": "plant", "nick": "Автор", "device_id": "dev-author"})
            assert r.status_code == 200 and r.json()["status"] == "created"
            for i in range(50):
                for dev, nick in (("dev-x", "Икс"), ("dev-y", "Игрек")):
                    rb = c.post("/api/brew-check", json={
                        "a": "stone", "b": "plant", "nick": nick, "device_id": dev})
                    assert rb.json()["status"] == "known"
            conn = sqlite3.connect(str(tmp_path / "dedup.db"))
            conn.row_factory = sqlite3.Row
            try:
                # brew-check больше не кредитует НИЧЕГО (читаемый путь)
                assert _echo_total(conn, "dev-author") == 0
                assert conn.execute(
                    "SELECT resonance_count AS rc FROM elements WHERE name='Дедупит'"
                ).fetchone()["rc"] == 0
                assert conn.execute(
                    "SELECT COUNT(*) AS c FROM resonance_seen").fetchone()["c"] == 0
            finally:
                conn.close()

    def test_100_rebrews_bounded_one_per_device(self, tmp_path, monkeypatch):
        srv, c = self._client(tmp_path, monkeypatch)
        with c:
            r = c.post("/api/discover", json={
                "a": "stone", "b": "plant", "nick": "Автор", "device_id": "dev-author"})
            assert r.json()["status"] == "created"
            for i in range(50):
                for dev, nick in (("dev-x", "Икс"), ("dev-y", "Игрек")):
                    rd = c.post("/api/discover", json={
                        "a": "stone", "b": "plant", "nick": nick, "device_id": dev})
                    assert rd.json()["status"] == "known"
            conn = sqlite3.connect(str(tmp_path / "dedup.db"))
            conn.row_factory = sqlite3.Row
            try:
                # delta баланса/эфира автора ограничен: 1 кредит на устройство
                assert _echo_total(conn, "dev-author") == 2
                assert conn.execute(
                    "SELECT balance AS b FROM echoes WHERE device_id='dev-author'"
                ).fetchone()["b"] == 2
                assert conn.execute(
                    "SELECT resonance_count AS rc FROM elements WHERE name='Дедупит'"
                ).fetchone()["rc"] == 2
                assert conn.execute(
                    "SELECT COUNT(*) AS c FROM resonance_seen").fetchone()["c"] == 2
            finally:
                conn.close()


class TestInitDbMigration:
    """Старая БД (без resonance_seen): init_db создаёт таблицу идемпотентно."""

    OLD_SCHEMA = """
    CREATE TABLE elements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL, color TEXT NOT NULL,
        layer INTEGER NOT NULL, category TEXT NOT NULL,
        author TEXT, created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pair_key TEXT NOT NULL UNIQUE,
        a TEXT NOT NULL, b TEXT NOT NULL,
        a_id INTEGER, b_id INTEGER, out_id INTEGER NOT NULL,
        discoverer TEXT, created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE players (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nick TEXT NOT NULL, device_id TEXT NOT NULL UNIQUE,
        created_at TEXT DEFAULT (datetime('now'))
    );
    """

    def test_old_db_gets_resonance_seen(self, tmp_path, monkeypatch):
        import server as srv
        db = str(tmp_path / "old.db")
        conn = sqlite3.connect(db)
        conn.executescript(self.OLD_SCHEMA)
        conn.commit()
        conn.close()
        monkeypatch.setattr(srv, "DB_PATH", db)
        srv.init_db()
        srv.init_db()  # двойной вызов — идемпотентность
        conn = sqlite3.connect(db)
        try:
            tabs = {r["name"] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'")}
            assert "resonance_seen" in tabs
        finally:
            conn.close()
