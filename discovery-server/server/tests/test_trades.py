"""S2 обмен картами: оффер/принятие/отмена/подарок поверх смены владельца строки.

Идиома — tests/test_social.py:36-67 (in-process TestClient + подмена DB_PATH +
явный init_db). Фикстура process_server здесь не годится: подпроцесс не даёт
подменить get_llm (Task 6 зовёт inbox, где Светик генерирует весточку) и
не даёт править created_at оффера для ленивой TTL. Просрочка во всех тестах
моделируется прямым UPDATE строки, а не _now_dt: так проверка не зависит от
того, в какой момент запускается pytest.
"""

import os
import sqlite3
import sys

from fastapi.testclient import TestClient

SERVER_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

TRADE_TABLES = ("trade_orders", "trade_counts")


class _LocalLLM:
    """Заглушка из tests/test_social.py:31-46. Без неё `_srv()` на машине с
    живым ключом в .env делает реальный HTTP-запрос при каждом inbox, где есть
    триггер Светика (Task 6 зовёт inbox за бейджем)."""
    provider = "local"
    api_key = ""
    models = []

    def generate_spirit_message(self, context, timeout=0):
        raise AssertionError("тест не должен звать LLM без явной подмены")

    def generate_card_identity(self, *args, **kwargs):
        raise AssertionError("тест не должен звать LLM без явной подмены")


def _srv(tmp_path, monkeypatch, llm=_LocalLLM()):
    sys.path.insert(0, SERVER_DIR)
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "trade.db"))
    if llm is not None:
        monkeypatch.setattr(srv, "get_llm", lambda: llm)
    return srv


def _client(srv):
    srv.init_db()
    return TestClient(srv.app)


def _player(client, nick, device_id):
    r = client.post("/api/me", json={"device_id": device_id, "nick": nick})
    assert r.status_code == 200, r.text
    return r.json()


def _tables(conn):
    return {r["name"] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}


def _columns(conn, table):
    """Форма таблицы целиком: dflt_value в сравнении обязателен, иначе DEFAULT
    разъедется между schema.sql и миграцией молча."""
    return [(r["name"], r["type"], r["notnull"], r["pk"], r["dflt_value"])
            for r in conn.execute("PRAGMA table_info(%s)" % table).fetchall()]


def _indexes(conn, table):
    """Что индекс покрывает, а не как он называется: имена совпадут и при
    разных столбцах, а живой VPS получит индекс вне планов запросов.
    index_xinfo (столбцы по порядку + unique) — как _columns выше, сверка
    текста DDL из sqlite_master ловила бы и формат вместо семантики."""
    out = {}
    for r in conn.execute("PRAGMA index_list(%s)" % table).fetchall():
        cols = [c["name"] for c in conn.execute(
            "PRAGMA index_xinfo(%s)" % r["name"]).fetchall() if c["key"]]
        out[r["name"]] = (r["unique"], cols)
    return out


def _seed(s, device_id, rows):
    """rows: [(craft_id, card_id, llm_name, crafted_at), …] — собрать карты в
    обход эндпоинта крафта (образец _seed_crafts из tests/test_sigil_api.py:236).
    Хроматик = card_id '' → is_chromatic 1."""
    conn = sqlite3.connect(s.DB_PATH)
    for craft_id, card_id, name, at in rows:
        conn.execute(
            "INSERT OR REPLACE INTO sigil_crafts"
            " (device_id, craft_id, rarity, llm_name, is_chromatic, card_id, crafted_at)"
            " VALUES (?, ?, 'common', ?, ?, ?, ?)",
            (device_id, craft_id, name, 1 if card_id == "" else 0, card_id, at),
        )
    conn.commit()
    conn.close()


class TestSchema:
    def test_fresh_db_has_trade_tables(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            have = _tables(conn)
        finally:
            conn.close()
        for t in TRADE_TABLES:
            assert t in have, (t, sorted(have))

    def test_migration_file_alone_creates_same_shape(self, tmp_path, monkeypatch):
        """Свежая БД (init_db) и живая (только 003_trades.sql) совпадают.

        Дублирование DDL — действующая конвенция (001_social.sql / 002_*.sql):
        без этого копии schema.sql и миграции разъезжаются молча, а живую БД
        правка schema.sql не касается вовсе.
        """
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            reference = {t: _columns(conn, t) for t in TRADE_TABLES}
            ref_idx = {t: _indexes(conn, t) for t in TRADE_TABLES}
        finally:
            conn.close()

        mig_path = os.path.join(SERVER_DIR, "migrations", "003_trades.sql")
        assert os.path.exists(mig_path), mig_path
        with open(mig_path, "r", encoding="utf-8") as f:
            ddl = f.read()
        bare = sqlite3.connect(str(tmp_path / "bare.db"))
        bare.row_factory = sqlite3.Row
        bare.executescript(ddl)
        try:
            for t in TRADE_TABLES:
                assert _columns(bare, t) == reference[t], t
                assert _indexes(bare, t) == ref_idx[t], t
        finally:
            bare.close()

    def test_init_db_twice_registers_version_three(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        srv.init_db()
        conn = srv.get_db()
        try:
            rows = conn.execute(
                "SELECT version, name FROM schema_version ORDER BY version").fetchall()
        finally:
            conn.close()
        names = [r["name"] for r in rows]
        assert "003_trades.sql" in names, names
        assert len(names) == len(set(names)), ("миграция применена дважды", names)


class TestHelpers:
    def test_pick_row_prefers_oldest_copy_deterministically(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [
            ("c2", "spark", "Искра вторая", "2026-02-01T00:00:00"),
            ("c1", "spark", "Искра первая", "2026-01-01T00:00:00"),
            ("c3", "coal", "Уголь", "2026-01-05T00:00:00"),
        ])
        conn = srv.get_db()
        try:
            assert srv._trade_pick_row(conn, "dev-a", "spark", "")["craft_id"] == "c1"
            assert srv._trade_pick_row(conn, "dev-a", "mist", "") is None
            assert srv._trade_pick_row(conn, "dev-b", "spark", "") is None
        finally:
            conn.close()

    def test_pick_row_chromatic_only_that_instance(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [("x1", "", "Хроматик", "2026-01-01T00:00:00")])
        _seed(srv, "dev-b", [("x1", "", "Чужой хроматик", "2026-01-01T00:00:00")])
        conn = srv.get_db()
        try:
            assert srv._trade_pick_row(conn, "dev-a", "", "x1")["craft_id"] == "x1"
            # обычная карта по чужому craft_id не подбирается: ветка требует
            # is_chromatic = 1, иначе «хроматик» украдал бы комплектные копии.
            _seed(srv, "dev-a", [("p1", "spark", "Искра", "2026-01-02T00:00:00")])
            assert srv._trade_pick_row(conn, "dev-a", "", "p1") is None
        finally:
            conn.close()

    def test_selector_enforces_xor_invariant(self, tmp_path, monkeypatch):
        from fastapi import HTTPException
        srv = _srv(tmp_path, monkeypatch)
        assert srv._trade_selector("spark", "") == ("spark", "")
        assert srv._trade_selector("", "x1") == ("", "x1")
        for bad in (("spark", "x1"), ("", ""), ("  ", " ")):
            try:
                srv._trade_selector(bad[0], bad[1])
                assert False, bad
            except HTTPException as e:
                assert (e.status_code, e.detail) == (422, "bad_selector"), bad

    def test_week_counter_upsert_and_ttl_cutoff(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        conn = srv.get_db()
        try:
            assert srv._trade_week_count(conn, "2026-W43", "dev-a") == 0
            srv._trade_count_up(conn, "2026-W43", "dev-a")
            srv._trade_count_up(conn, "2026-W43", "dev-a")
            conn.commit()
            assert srv._trade_week_count(conn, "2026-W43", "dev-a") == 2
            assert srv._trade_week_count(conn, "2026-W44", "dev-a") == 0
            # cutoff строго раньше «сейчас» на TRADE_TTL_DAYS суток
            assert srv._trade_ttl_cutoff() < srv._now_iso()
        finally:
            conn.close()
