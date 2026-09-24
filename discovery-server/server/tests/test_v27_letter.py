"""Письмо Светика (v27): ежедневная загадка-пара, конверты, вечный счётчик."""
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
    def __init__(self, name: str):
        self.name = name

    def generate(self, a, b, a_name, b_name, pair_key):
        return {"combinable": True, "name": self.name,
                "glyph": "fire", "description": "лор"}


class _FakeHint:
    def __init__(self):
        self.calls = 0

    def generate_hint(self, a_name, b_name):
        self.calls += 1
        return {"hint": f"Шёпот про {a_name} и {b_name} номер {self.calls}"}


class TestHintGen:
    def test_mock_hint_has_no_full_names(self):
        from gen_llm import LLMGenerator
        h = LLMGenerator(provider="mock").generate_hint("Огонь", "Вода")["hint"]
        assert "Огонь" not in h and "Вода" not in h
        assert "О" in h and "В" in h  # первые буквы — можно

    def test_validate_hint(self):
        from gen_llm import validate_hint
        assert validate_hint({"hint": "коротко"}) is None
        assert validate_hint({"hint": "x" * 401}) is None
        assert validate_hint({}) is None
        assert validate_hint({"hint": "Тёплый намёк на пару"})["hint"].startswith("Тёплый")


class TestLetterPick:
    def test_cached_and_generated_once(self):
        conn = _fresh_conn()
        fake = _FakeHint()
        r1 = server._ensure_letter(conn, "dev-a", "А", "2026-01-05", fake)
        r2 = server._ensure_letter(conn, "dev-a", "А", "2026-01-05", fake)
        assert r1["hint"] == r2["hint"] and r1["a"] == r2["a"]
        assert fake.calls == 1  # 1 LLM-запрос, дальше кэш
        conn.close()

    def test_deterministic_pair(self):
        c1, c2 = _fresh_conn(), _fresh_conn()
        r1 = server._ensure_letter(c1, "dev-a", "А", "2026-01-05", _FakeHint())
        r2 = server._ensure_letter(c2, "dev-a", "А", "2026-01-05", _FakeHint())
        assert (r1["a"], r1["b"]) == (r2["a"], r2["b"])
        c1.close()
        c2.close()

    def test_excludes_own_and_lettered(self):
        conn = _fresh_conn()
        # своё первооткрытие — не кандидат
        server._generate_for_pair(
            conn, "stone", "plant", server.canonical_pair_key("stone", "plant"),
            "Перво", llm=_FakeLLM("Звенигород"))
        conn.commit()
        keys = {r["pair_key"] for r in server._letter_candidates(conn, "Перво", "dev-a")}
        assert "plant|stone" not in keys
        assert len(keys) > 0  # стартовые рецепты подходят
        # загаданная пара исключается из следующих дней
        r1 = server._ensure_letter(conn, "dev-a", "Перво", "2026-01-05", _FakeHint())
        keys2 = {r["pair_key"] for r in server._letter_candidates(conn, "Перво", "dev-a")}
        assert f"{r1['a']}|{r1['b']}" not in keys2
        conn.close()

    def test_backlog_pruned_to_seven(self):
        conn = _fresh_conn()
        for i in range(1, 9):
            conn.execute(
                "INSERT INTO letters (device_id, day, a, b, a_name, b_name, hint) "
                "VALUES (?, ?, 'fire', 'water', 'О', 'В', 'шёпот')",
                ("dev-a", f"2026-01-{i:02d}"),
            )
        conn.commit()
        server._ensure_letter(conn, "dev-a", "А", "2026-01-10", _FakeHint())
        n = conn.execute(
            "SELECT COUNT(*) AS c FROM letters WHERE device_id='dev-a' AND solved=0"
        ).fetchone()["c"]
        assert n == 7
        assert conn.execute(
            "SELECT COUNT(*) AS c FROM letters WHERE device_id='dev-a' AND day='2026-01-01'"
        ).fetchone()["c"] == 0  # самое старое ушло в архив
        conn.close()

    def test_llm_down_postpones_day(self):
        from gen_llm import LLMError

        class _Down:
            def generate_hint(self, a, b):
                raise LLMError("всё упало")

        conn = _fresh_conn()
        assert server._ensure_letter(conn, "dev-a", "А", "2026-01-05", _Down()) is None
        assert conn.execute("SELECT COUNT(*) AS c FROM letters").fetchone()["c"] == 0
        # день догенерируется позже
        assert server._ensure_letter(conn, "dev-a", "А", "2026-01-05", _FakeHint()) is not None
        conn.close()


def _client_for(tmp_path, monkeypatch, fake):
    from fastapi.testclient import TestClient
    sys.path.insert(0, os.path.join(_here, ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "letter.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: fake)
    return TestClient(srv.app), str(tmp_path / "letter.db")


class TestLetterHttp:
    def test_today_and_solve_flow(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-a", "nick": "Читун"})
            g1 = c.get("/api/letter/today", params={"device_id": "dev-a"}).json()
            assert g1["ok"] is True and g1["today"] is not None
            assert g1["today"]["hint"].startswith("Шёпот")
            assert g1["solved_total"] == 0
            day = g1["today"]["day"]
            g2 = c.get("/api/letter/today", params={"device_id": "dev-a"}).json()
            assert g2["today"]["hint"] == g1["today"]["hint"]  # кэш, не реген
            # слаги ответа клиент не видит — подсматриваем в БД, шлём в обратном порядке
            row = sqlite3.connect(db).execute(
                "SELECT a, b FROM letters WHERE device_id='dev-a' AND day=?", (day,),
            ).fetchone()
            s = c.post("/api/letter/solve",
                       json={"device_id": "dev-a", "a": row[1], "b": row[0]}).json()
            assert (s["matched"], s["day"], s["solved_total"], s["milestone"]) == (True, day, 1, False)
            s2 = c.post("/api/letter/solve",
                        json={"device_id": "dev-a", "a": row[0], "b": row[1]}).json()
            assert (s2["matched"], s2["solved_total"]) == (False, 1)  # повтор — мимо
            s3 = c.post("/api/letter/solve",
                        json={"device_id": "dev-a", "a": "zzz", "b": "yyy"}).json()
            assert (s3["matched"], s3["solved_total"]) == (False, 1)  # чужая пара — мимо
            g3 = c.get("/api/letter/today", params={"device_id": "dev-a"}).json()
            assert g3["today"]["solved"] is True and g3["solved_total"] == 1

    def test_milestone_every_fifth(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-m", "nick": "Марк"})
            # 4 старых недоделки c разными парами + сегодняшнее = 5
            conn = sqlite3.connect(db)
            pairs = [("fire", "water"), ("fire", "earth"), ("fire", "air"), ("water", "earth")]
            for i, (a, b) in enumerate(pairs, start=1):
                conn.execute(
                    "INSERT INTO letters (device_id, day, a, b, a_name, b_name, hint) "
                    "VALUES ('dev-m', ?, ?, ?, 'О', 'В', 'ш')",
                    (f"2026-01-{i:02d}", a, b),
                )
            conn.commit()
            conn.close()
            g = c.get("/api/letter/today", params={"device_id": "dev-m"}).json()
            assert len(g["backlog"]) == 4
            today_row = sqlite3.connect(db).execute(
                "SELECT a, b FROM letters WHERE device_id='dev-m' AND day=?",
                (g["today"]["day"],),
            ).fetchone()
            last = None
            for (a, b) in pairs + [(today_row[0], today_row[1])]:
                last = c.post("/api/letter/solve",
                              json={"device_id": "dev-m", "a": a, "b": b}).json()
                assert last["matched"] is True
            assert last["solved_total"] == 5 and last["milestone"] is True

    def test_reveal_after_two_days(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-r", "nick": "Рита"})
            # T09/U8 (c): дата в единой серверной шкале (server._date_minus),
            # НЕ хост-локальная date.today() — иначе тест разъезжается с
            # серверным _today() на хостах вне нулевого смещения.
            old = server._date_minus(3)
            conn = sqlite3.connect(db)
            conn.execute(
                "INSERT INTO letters (device_id, day, a, b, a_name, b_name, hint) "
                "VALUES ('dev-r', ?, 'fire', 'water', 'Огонь', 'Вода', 'шёпот')",
                (old,),
            )
            conn.commit()
            conn.close()
            g = c.get("/api/letter/today", params={"device_id": "dev-r"}).json()
            old_l = g["backlog"][0]
            assert old_l["revealed"] is True
            assert old_l["a_name"] == "Огонь" and old_l["b_name"] == ""
            assert old_l["known_b"] == [[0, "В"]] and old_l["known_a"] == []
            assert old_l["len_a"] == 5 and old_l["len_b"] == 4
            assert "a" not in old_l and "b" not in old_l
            assert g["today"]["revealed"] is False

    def test_no_answer_leak(self, tmp_path, monkeypatch):
        import sqlite3
        c, db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            c.post("/api/me", json={"device_id": "dev-l", "nick": "Лика"})
            # T09/U8 (c): серверная шкала вместо хост-локальной даты
            yest = server._date_minus(1)
            conn = sqlite3.connect(db)
            conn.execute(
                "INSERT INTO letters (device_id, day, a, b, a_name, b_name, hint) "
                "VALUES ('dev-l', ?, 'fire', 'water', 'Огонь', 'Вода', 'шёпот')",
                (yest,),
            )
            conn.commit()
            conn.close()
            g = c.get("/api/letter/today", params={"device_id": "dev-l"}).json()
            t = g["today"]
            assert "a" not in t and "b" not in t
            assert t["a_name"] == "" and t["b_name"] == ""
            assert t["len_a"] > 0 and t["len_b"] > 0
            assert t["known_a"] == [] and t["known_b"] == []
            y = g["backlog"][0]
            assert y["a_name"] == "" and y["known_a"] == [[0, "О"]]
            assert y["revealed"] is False

    def test_unknown_device_empty(self, tmp_path, monkeypatch):
        c, _db = _client_for(tmp_path, monkeypatch, _FakeHint())
        with c:
            g = c.get("/api/letter/today", params={"device_id": "nope"}).json()
            # письмо создаётся и без регистрации (ник пустой) — механика доступна всем
            assert g["ok"] is True and g["today"] is not None
            assert g["solved_total"] == 0


class TestLetterMigration:
    def test_old_db_gets_letters(self, tmp_path):
        import sqlite3
        import subprocess

        db = str(tmp_path / "oldletter.sqlite")
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
            "assert 'letters' in tabs, tabs\n"
            "print('LETTER_MIGRATION_OK')\n"
        )
        r = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=60
        )
        assert r.returncode == 0, "stderr: %s\nstdout: %s" % (r.stderr, r.stdout)
        assert "LETTER_MIGRATION_OK" in r.stdout
