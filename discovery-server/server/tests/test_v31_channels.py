"""U6/T05: разнесение challenge/vein-каналов очков и ноль наград при reused.

Инварианты:
1. vein-очки живут в vein_points и НЕ создают строку в challenge_scores:
   попадание в жилу больше не гасит won за реальное выполнение цели дня;
   won=true ровно один раз на устройство за день, completions считает только
   реальные выполнения, my_points = challenge + vein (игрок не теряет очки).
2. reused (дедуп имени, пара привязана к существующему веществу) — ноль
   серверных наград: ни world_event, ни challenge/vein-очков, ни звания
   «ПЕРВООТКРЫТИЕ»; сам linking (рецепт → существующий элемент) сохраняется.
3. Миграция старых строк challenge_scores идемпотентна: completed_at
   проставляется только строкам challenge-канала (first_at — явный isoformat
   с 'T'); vein-строки остаются с NULL → их владельцы получают won при первом
   реальном выполнении (это ровно те, кому он был должен).

Тесты гоняются под pytest (нужен fastapi). Без него — компилируются;
pure-stdlib доказательство post-lock re-check лока: harness_lock_recheck_u6.py.
"""
import os
import sqlite3
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import seed  # noqa: E402
import server as srv  # noqa: E402

_PAIRS = [("mud", "stone"), ("water", "mud"), ("mud", "air"), ("fire", "mud"),
          ("gold", "mud"), ("ice", "mud"), ("metal", "mud"), ("glass", "mud"),
          ("wood", "mud"), ("lightning", "mud"), ("crystal", "mud"),
          ("water", "stone"), ("wood", "stone"), ("glass", "air")]


def _is_unknown(conn, a, b):
    pk = srv.canonical_pair_key(a, b)
    if conn.execute("SELECT 1 FROM recipes WHERE pair_key = ?", (pk,)).fetchone():
        return False
    return not conn.execute(
        "SELECT 1 FROM rejected_pairs WHERE pair_key = ?", (pk,)).fetchone()


def _unknown_pair(db_path, avoid, used):
    """Пара неизвестных элементов, не задевающая целевой ингредиент дня."""
    conn = sqlite3.connect(db_path)
    try:
        for a, b in _PAIRS:
            if a in avoid or b in avoid or (a, b) in used:
                continue
            if _is_unknown(conn, a, b):
                return a, b
    finally:
        conn.close()
    raise AssertionError("нет свободной неизвестной пары")


def _unknown_partner(db_path, required, avoid):
    """Элемент s, что пара (required, s) неизвестна серверу."""
    conn = sqlite3.connect(db_path)
    try:
        for s in [b for a, b in _PAIRS if a == required] + \
                 [a for a, b in _PAIRS if b == required] + \
                 ["mud", "stone", "water", "air", "fire", "gold", "ice", "metal"]:
            if s == required or s in avoid:
                continue
            if _is_unknown(conn, required, s):
                return s
    finally:
        conn.close()
    raise AssertionError(f"нет свободного партнёра для {required}")


class _PlainGen:
    """Генератор уникальных имён вне реестра веществ (без цифр/дефисов,
    иначе _generate_for_pair завернёт как not_combinable)."""

    WORDS = ["Туманник", "Златоцвет", "Мхоед", "Пепелень", "Соляник",
             "Ледянник", "Парников", "Мерцалина"]

    def __init__(self, tag=None):
        self.tag = tag
        self.calls = 0

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        # имя без цифр/дефисов/подчёркиваний — иначе генератор завернёт его
        res = {"combinable": True,
               "name": self.WORDS[self.calls % len(self.WORDS)] + "ный"}
        self.calls += 1
        if self.tag:
            res["tag"] = self.tag
        res["glyph"] = "mist"
        res["description"] = "Тестовое вещество."
        return res


class _NamedGen:
    """Генератор, всегда выдающий занятое имя → ветка дедупа (reused)."""

    def __init__(self, name):
        self.name = name
        self.calls = 0

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        self.calls += 1
        return {"combinable": True, "name": self.name, "glyph": "mist",
                "description": "Тест."}


def _client_for(tmp_path, monkeypatch, fake_llm):
    from fastapi.testclient import TestClient
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "channels.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: fake_llm)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)  # без пауз между варами
    return TestClient(srv.app)


class TestChannels:
    def test_vein_hit_then_daily_completion_wins_once(self, tmp_path, monkeypatch):
        gen = _PlainGen()
        c = _client_for(tmp_path, monkeypatch, gen)
        db = str(tmp_path / "channels.db")
        with c:
            week = c.get("/api/week/status", params={"device_id": "dev-c"}).json()
            tag1 = week["vein"]["tag1"]
            target = c.get("/api/challenge", params={"device_id": "dev-c"}).json()["target"]

            # 1) попадание в жилу: vein-очки есть, challenge-канала нет
            gen.tag = tag1
            a, b = _unknown_pair(db, avoid={target}, used=set())
            r1 = c.post("/api/discover", json={
                "a": a, "b": b, "nick": "Жилец", "device_id": "dev-c"}).json()
            assert r1["status"] == "created" and r1["discovery"]["reused"] is False
            assert r1["vein"] is not None and r1["vein"]["points"] == srv.VEIN_POINTS
            assert r1["challenge"]["won"] is False
            conn = sqlite3.connect(db)
            try:
                assert conn.execute(
                    "SELECT points FROM vein_points WHERE device_id='dev-c' AND day = ?",
                    (srv._today(),)).fetchone()[0] == srv.VEIN_POINTS
                assert conn.execute(
                    "SELECT 1 FROM challenge_scores WHERE device_id='dev-c'").fetchone() is None, \
                    "жила больше не создаёт строку дневной цели"
            finally:
                conn.close()
            body = c.get("/api/challenge", params={"device_id": "dev-c"}).json()
            assert body["completions"] == 0, "vein-only не накручивает completions"
            assert body["my_points"] == srv.VEIN_POINTS, "очки игрока сохранены"

            # 2) реальное выполнение цели дня: won=true
            gen.tag = None
            partner = _unknown_partner(db, target, avoid={a, b})
            r2 = c.post("/api/discover", json={
                "a": target, "b": partner,
                "nick": "Жилец", "device_id": "dev-c"}).json()
            assert r2["status"] == "created"
            assert r2["challenge"]["won"] is True, \
                "игрок с vein-попаданием обязан получить won за реальное выполнение"

            # 3) ещё одно выполнение цели за день — won больше не выдаётся
            partner2 = _unknown_partner(db, target, avoid={a, b, partner})
            r3 = c.post("/api/discover", json={
                "a": target, "b": partner2,
                "nick": "Жилец", "device_id": "dev-c"}).json()
            assert r3["status"] == "created"
            assert r3["challenge"]["won"] is False
            body = c.get("/api/challenge", params={"device_id": "dev-c"}).json()
            assert body["completions"] == 1, "устройство засчитано ровно один раз"

    def test_reused_no_rewards(self, tmp_path, monkeypatch):
        existing_name = "Огонь"  # сидовое вещество: LLM «снова» выдаёт его имя
        c = _client_for(tmp_path, monkeypatch, _NamedGen(existing_name))
        db = str(tmp_path / "channels.db")
        with c:
            conn = sqlite3.connect(db)
            try:
                fire_id = conn.execute(
                    "SELECT id FROM elements WHERE name = ?", (existing_name,)).fetchone()[0]
            finally:
                conn.close()
            used = set()
            for _ in range(3):  # фарш нескольких пар на одно имя
                a, b = _unknown_pair(db, avoid=set(), used=used)
                used.add((a, b))
                r = c.post("/api/discover", json={
                    "a": a, "b": b, "nick": "Фармер", "device_id": "dev-f"}).json()
                assert r["status"] == "created"
                assert r["discovery"]["reused"] is True
                assert r["challenge"] is None and r["vein"] is None
                assert "ПЕРВООТКРЫТИЕ" not in r["message"]
            conn = sqlite3.connect(db)
            try:
                assert conn.execute(
                    "SELECT COUNT(*) FROM world_events WHERE discoverer = 'Фармер'"
                ).fetchone()[0] == 0, "reused не спамит ленту"
                assert conn.execute(
                    "SELECT COUNT(*) FROM challenge_scores WHERE device_id = 'dev-f'"
                ).fetchone()[0] == 0
                assert conn.execute(
                    "SELECT COUNT(*) FROM vein_points WHERE device_id = 'dev-f'"
                ).fetchone()[0] == 0
                # linking сохранён: все три пары ведут к тому же веществу
                rows = conn.execute(
                    "SELECT out_id FROM recipes WHERE discoverer_device = 'dev-f'"
                ).fetchall()
                assert len(rows) == 3 and all(x[0] == fire_id for x in rows)
            finally:
                conn.close()
            body = c.get("/api/challenge", params={"device_id": "dev-f"}).json()
            assert body["my_points"] == 0 and body["completions"] == 0

    def test_linked_not_counted_in_public_counters(self, tmp_path, monkeypatch):
        """T28 (I-2): linked-строки не двигают ни зал славы, ни рейтинг, ни
        ordinal «первооткрыватель №N» в brew-check.

        test_reused_no_rewards закрыл экономику (очки/события), но _link_existing
        пишет recipes.discoverer=ник, и публичные счётчики считали дедуп-варки
        как первооткрытия — фарм места оставался. Мутации, красящие кейс:
        убрать `AND r.linked = 0` в hall-of-fame (count станет 4 вместо 1) или
        в rating.discoveries (то же), либо писать linked=0 в _link_existing
        (тогда краснеет разметка created/linked); убрать `linked = 0` из seq-
        запроса brew-check — discoverer.seq станет 4 вместо 2.
        """
        existing_name = "Огонь"  # сидовое вещество — цель для ветки дедупа
        gen = _PlainGen()
        c = _client_for(tmp_path, monkeypatch, gen)
        db = str(tmp_path / "channels.db")
        with c:
            used = set()
            a, b = _unknown_pair(db, avoid=set(), used=used)
            used.add((a, b))
            r1 = c.post("/api/discover", json={
                "a": a, "b": b, "nick": "Славик", "device_id": "dev-s"}).json()
            assert r1["status"] == "created" and r1["discovery"]["reused"] is False
            # дальше — всегда занятое имя: все три варки уходят в linked
            monkeypatch.setattr(srv, "get_llm", lambda: _NamedGen(existing_name))
            last_linked = None
            for _ in range(3):
                a, b = _unknown_pair(db, avoid=set(), used=used)
                used.add((a, b))
                last_linked = (a, b)
                r = c.post("/api/discover", json={
                    "a": a, "b": b, "nick": "Славик", "device_id": "dev-s"}).json()
                assert r["discovery"]["reused"] is True
            conn = sqlite3.connect(db)
            try:
                rows = conn.execute(
                    "SELECT linked, COUNT(*) FROM recipes WHERE discoverer = 'Славик'"
                    " GROUP BY linked").fetchall()
                assert sorted(rows) == [(0, 1), (1, 3)], "разметка created/linked на месте"
            finally:
                conn.close()
            body = c.get("/api/rating", params={"device_id": "dev-s"}).json()
            assert body["me"]["discoveries"] == 1, \
                "rating считает только created-варки (1), а не все 4 строки ника"
            hall = c.get("/api/hall-of-fame").json()
            entry = next(e for e in hall["hall"] if e["nick"] == "Славик")
            assert entry["count"] == 1, "зал славы — тоже только первооткрытия"
            # brew-check известной linked-пары: тот же ник, но порядковый номер
            # считается по created-варкам → 2 (одна была раньше), а не 4.
            bc = c.post("/api/brew-check", json={
                "a": last_linked[0], "b": last_linked[1],
                "nick": "Славик", "device_id": "dev-s"}).json()
            assert bc["found"] is True and bc["discoverer"]["nick"] == "Славик"
            assert bc["discoverer"]["seq"] == 2, \
                "ordinal первооткрывателя не растёт от дедуп-варок"


class TestLegacyMigration:
    """Прогрев prod-БД: колонки нет, в строках смешаны vein-очки и выполнения.

    Различник каналов — first_at: _score_challenge вставляет явный isoformat
    (разделитель 'T'), vein-путь — default datetime('now') (пробел)."""

    def _old_days(self, conn):
        return conn.execute(
            "INSERT INTO challenge_scores (day, device_id, nick, points, first_at) VALUES"
            " ('2025-01-01', 'dev-vein', 'Жила', 4, '2025-01-01 09:00:00'),"  # vein-формат
            " ('2025-01-01', 'dev-chal', 'Цель', 1, '2025-01-01T09:30:00.000001')"
        )

    def test_completed_at_backfill_is_idempotent_and_scoped(self, tmp_path, monkeypatch):
        db = str(tmp_path / "legacy.db")
        monkeypatch.setattr(srv, "DB_PATH", db)
        srv.init_db()
        conn = sqlite3.connect(db)
        conn.execute("ALTER TABLE challenge_scores DROP COLUMN completed_at")
        self._old_days(conn)
        conn.commit()
        conn.close()

        srv.init_db()  # догоняющая миграция: ALTER + scoped backfill
        conn = sqlite3.connect(db)
        conn.row_factory = sqlite3.Row
        try:
            assert conn.execute(
                "SELECT completed_at FROM challenge_scores WHERE device_id = 'dev-chal'"
            ).fetchone()[0] == "2025-01-01T09:30:00.000001", "isoformat-строка размечена"
            assert conn.execute(
                "SELECT completed_at FROM challenge_scores WHERE device_id = 'dev-vein'"
            ).fetchone()[0] is None, "vein-строка не размечена (won её владельцу должен)"
            srv.init_db()  # идемпотентность: колонка уже есть — ничего не дублируется
            conn2 = sqlite3.connect(db)
            try:
                assert conn2.execute(
                    "SELECT COUNT(*) FROM challenge_scores WHERE device_id = 'dev-chal'"
                ).fetchone()[0] == 1
            finally:
                conn2.close()
        finally:
            conn.close()

    def test_legacy_vein_row_gets_won_once_then_quiet(self, tmp_path, monkeypatch):
        """Прогрев на сегодняшнем дне: владелец vein-строки получает won ровно
        один раз, дальше — только очки.

        БД собирается вручную в прежнем формате (колонки completed_at нет) и
        только потом прогоняется init_db() — ровно то, что происходит на проде
        при деплое ветки. Вариант «DROP COLUMN и сразу _score_challenge» падал
        OperationalError (INSERT/WHERE в server._score_challenge называют
        completed_at по имени) и не мог пройти ни при каком коде.
        """
        db = str(tmp_path / "legacy2.db")
        conn = sqlite3.connect(db)
        conn.execute(
            "CREATE TABLE challenge_scores (day TEXT NOT NULL, device_id TEXT NOT NULL,"
            " nick TEXT NOT NULL, points INTEGER NOT NULL DEFAULT 0,"
            " first_at TEXT DEFAULT (datetime('now')), PRIMARY KEY (day, device_id))")
        day = srv._today()
        conn.execute(
            "INSERT INTO challenge_scores (day, device_id, nick, points, first_at)"
            " VALUES (?, 'dev-vein', 'Жила', 2, ?)", (day, "2025-01-01 09:00:00"))
        conn.commit()
        conn.close()
        monkeypatch.setattr(srv, "DB_PATH", db)
        srv.init_db()  # ALTER + scoped backfill: vein-строка остаётся с NULL
        conn = sqlite3.connect(db)
        conn.row_factory = sqlite3.Row
        ch = srv._ensure_challenge(conn)

        # легаси vein-владелец впервые реально выполняет цель → won ровно один раз
        w = srv._score_challenge(conn, ch["target"], "mud", "Жила", "dev-vein")
        assert w["won"] is True
        w2 = srv._score_challenge(conn, ch["target"], "air", "Жила", "dev-vein")
        assert w2["won"] is False
        # completions считает только completed_at: один день — одна засчитка
        n = conn.execute(
            "SELECT COUNT(*) c FROM challenge_scores"
            " WHERE day = ? AND completed_at IS NOT NULL", (day,)).fetchone()["c"]
        assert n == 1
        conn.close()

    def test_old_db_without_tables_gets_channels(self, tmp_path, monkeypatch):
        db = str(tmp_path / "old.db")
        conn = sqlite3.connect(db)
        conn.execute(
            "CREATE TABLE challenge_scores (day TEXT NOT NULL, device_id TEXT NOT NULL,"
            " nick TEXT NOT NULL, points INTEGER NOT NULL DEFAULT 0,"
            " first_at TEXT DEFAULT (datetime('now')), PRIMARY KEY (day, device_id))")
        self._old_days(conn)
        conn.commit()
        conn.close()
        monkeypatch.setattr(srv, "DB_PATH", db)
        srv.init_db()
        srv.init_db()  # идемпотентно
        conn = sqlite3.connect(db)
        try:
            cols = {r[1] for r in conn.execute("PRAGMA table_info(challenge_scores)")}
            assert "completed_at" in cols
            tabs = {r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'")}
            assert "vein_points" in tabs
            assert conn.execute(
                "SELECT completed_at FROM challenge_scores WHERE device_id = 'dev-chal'"
            ).fetchone()[0] == "2025-01-01T09:30:00.000001"
            assert conn.execute(
                "SELECT completed_at FROM challenge_scores WHERE device_id = 'dev-vein'"
            ).fetchone()[0] is None
        finally:
            conn.close()
