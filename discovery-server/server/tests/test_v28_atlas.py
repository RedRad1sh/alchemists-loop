"""Страница Атласа (v28): общемировая загадка дня, альбом, веха каждые 10."""
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


class _FakeHint:
    def __init__(self):
        self.calls = 0

    def generate_hint(self, a_name, b_name):
        self.calls += 1
        return {"hint": f"Загадка про {a_name} и {b_name} номер {self.calls}"}


class TestAtlasPick:
    def test_cached_and_generated_once(self):
        conn = _fresh_conn()
        fake = _FakeHint()
        r1 = server._ensure_atlas(conn, "2026-02-05", fake)
        r2 = server._ensure_atlas(conn, "2026-02-05", fake)
        assert r1 is not None and r2 is not None
        assert r1["riddle"] == r2["riddle"] and fake.calls == 1
        conn.close()

    def test_shared_global_no_repeat(self):
        conn = _fresh_conn()
        fake = _FakeHint()
        d1 = server._ensure_atlas(conn, "2026-02-05", fake)
        d2 = server._ensure_atlas(conn, "2026-02-06", fake)
        # одна страница на всех: пара дня не зависит от устройства (его нет в сиде)
        assert d1 is not None and d2 is not None
        p1 = tuple(sorted([d1["a"], d1["b"]]))
        p2 = tuple(sorted([d2["a"], d2["b"]]))
        assert p1 != p2  # антиповтор: вчерашняя пара исключена
        conn.close()

    def test_llm_down_postpones_day(self):
        from gen_llm import LLMError

        class _Down:
            def generate_hint(self, a, b):
                raise LLMError("всё упало")

        conn = _fresh_conn()
        assert server._ensure_atlas(conn, "2026-02-05", _Down()) is None
        assert conn.execute("SELECT COUNT(*) AS c FROM atlas_pages").fetchone()["c"] == 0
        assert server._ensure_atlas(conn, "2026-02-05", _FakeHint()) is not None
        conn.close()


def _client_for(tmp_path, monkeypatch, fake):
    from fastapi.testclient import TestClient
    sys.path.insert(0, os.path.join(_here, ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "atlas.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: fake)
    return TestClient(srv.app), str(tmp_path / "atlas.db")


class TestAtlasHttp:
    def test_today_and_solve_flow(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-a", "nick": "Ат"})
            g1 = c.get("/api/atlas/today", params={"device_id": "dev-a"}).json()
            assert g1["ok"] is True and g1["today"] is not None
            assert g1["today"]["riddle"].startswith("Загадка")
            assert g1["today"]["solved_by_me"] is False
            assert g1["today"]["solvers"] == 0
            assert g1["solved_total"] == 0
            # слаги ответа не утекают никогда; имена пусты, пока не разгадал
            assert "a" not in g1["today"] and "b" not in g1["today"]
            assert g1["today"]["a_name"] == "" and g1["today"]["b_name"] == ""
            assert g1["today"]["len_a"] > 0 and g1["today"]["len_b"] > 0
            row = sqlite3.connect(db).execute(
                "SELECT a, b FROM atlas_pages WHERE day=?", (g1["today"]["day"],),
            ).fetchone()
            s = c.post("/api/atlas/solve",
                       json={"device_id": "dev-a", "a": row[1], "b": row[0]}).json()
            assert (s["matched"], s["solved_total"], s["milestone"]) == (True, 1, False)
            s2 = c.post("/api/atlas/solve",
                        json={"device_id": "dev-a", "a": row[0], "b": row[1]}).json()
            assert (s2["matched"], s2["solved_total"]) == (False, 1)  # повтор — мимо
            # разгадавшему имена своей страницы видны
            g1b = c.get("/api/atlas/today", params={"device_id": "dev-a"}).json()
            assert g1b["today"]["solved_by_me"] is True
            assert g1b["today"]["a_name"] != "" and g1b["today"]["b_name"] != ""
            # второй игрок видит счётчик разгадок и ту же страницу
            g2 = c.get("/api/atlas/today", params={"device_id": "dev-b"}).json()
            assert g2["today"]["solvers"] == 1
            assert g2["today"]["riddle"] == g1["today"]["riddle"]
            assert g2["today"]["solved_by_me"] is False

    def test_milestone_every_tenth(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-m", "nick": "М"})
            conn = sqlite3.connect(db)
            for i in range(1, 10):
                conn.execute(
                    "INSERT INTO atlas_solves (device_id, day) VALUES ('dev-m', ?)",
                    (f"2026-01-{i:02d}",),
                )
            conn.commit()
            conn.close()
            g = c.get("/api/atlas/today", params={"device_id": "dev-m"}).json()
            assert g["solved_total"] == 9
            row = sqlite3.connect(db).execute(
                "SELECT a, b FROM atlas_pages WHERE day=?", (g["today"]["day"],),
            ).fetchone()
            s = c.post("/api/atlas/solve",
                       json={"device_id": "dev-m", "a": row[0], "b": row[1]}).json()
            assert s["matched"] is True
            assert s["solved_total"] == 10 and s["milestone"] is True

    def test_history_album(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            conn = sqlite3.connect(db)
            conn.execute(
                "INSERT INTO atlas_pages (day, a, b, a_name, b_name, riddle) "
                "VALUES ('2026-01-01', 'fire', 'water', 'Огонь', 'Вода', 'старая')"
            )
            conn.commit()
            conn.close()
            g = c.get("/api/atlas/today", params={"device_id": "dev-a"}).json()
            assert len(g["history"]) == 1
            assert g["history"][0]["a_name"] == "Огонь"
            assert g["history"][0]["riddle"] == "старая"
            # вчерашнюю пару разгадать задним числом нельзя
            s = c.post("/api/atlas/solve",
                       json={"device_id": "dev-a", "a": "fire", "b": "water"}).json()
            # (совпало бы, только если сегодня выпала та же пара — антиповтор исключает)
            assert s["solved_total"] == 0

    def test_unknown_device_empty(self, tmp_path, monkeypatch):
        c, _db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            g = c.get("/api/atlas/today", params={"device_id": "nope"}).json()
            assert g["ok"] is True and g["today"] is not None
            assert g["solved_total"] == 0


class TestAtlasMigration:
    def test_old_db_gets_atlas(self, tmp_path):
        import sqlite3
        import subprocess

        db = str(tmp_path / "oldatlas.sqlite")
        conn = sqlite3.connect(db)
        conn.execute(
            "CREATE TABLE elements (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL, color TEXT NOT NULL, "
            "layer INTEGER NOT NULL, category TEXT NOT NULL, author TEXT)"
        )
        conn.execute(
            "CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "nick TEXT NOT NULL, device_id TEXT NOT NULL UNIQUE)"
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
            "tabs = {r[0] for r in conn.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")}\n"
            "assert 'atlas_pages' in tabs and 'atlas_solves' in tabs, tabs\n"
            "print('ATLAS_MIGRATION_OK')\n"
        )
        r = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=60
        )
        assert r.returncode == 0, "stderr: %s\nstdout: %s" % (r.stderr, r.stdout)
        assert "ATLAS_MIGRATION_OK" in r.stdout
