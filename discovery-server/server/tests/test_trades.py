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
from datetime import datetime, timedelta

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


def _order(s, maker, taker, state, created_at):
    """Строка trade_orders в обход ручки (её не будет до Task 3). created_at — ISO."""
    conn = sqlite3.connect(s.DB_PATH)
    conn.execute(
        "INSERT INTO trade_orders (maker_device, taker_device, give_card_id,"
        " want_card_id, state, created_at, updated_at) VALUES (?, ?, 'spark', 'ice',"
        " ?, ?, ?)", (maker, taker, state, created_at, created_at))
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
        """Селектор по card_id выбирает САМУЮ СТАРУЮ копию.

        Порядок craft_id здесь умышленно ПРОТИВОРЕЧИТ порядку crafted_at: у
        dev-a самая старая «Искра» — z9 (2026-01-01), а лексикографически
        раньше идёт a1 (2026-03-01). Без `ORDER BY crafted_at` выбрался бы a1,
        поэтому тест краснеет на `ORDER BY craft_id` (→ a1) и на
        `ORDER BY crafted_at DESC` (→ a1). Снятие второго ключа и ORDER BY
        целиком ловит соседний test_pick_row_breaks_ties_by_craft_id: там
        порядок вставки не совпадает с порядком craft_id.
        """
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [
            ("z9", "spark", "Искра самая старая", "2026-01-01T00:00:00"),
            ("a1", "spark", "Искра самая свежая", "2026-03-01T00:00:00"),
            ("b2", "coal", "Уголь", "2026-01-05T00:00:00"),
        ])
        conn = srv.get_db()
        try:
            assert srv._trade_pick_row(conn, "dev-a", "spark", "")["craft_id"] == "z9"
            assert srv._trade_pick_row(conn, "dev-a", "mist", "") is None
            # без `device_id = ?` в ветке карты запрос для dev-b нашёл бы
            # копию dev-a и вернул z9 вместо None.
            assert srv._trade_pick_row(conn, "dev-b", "spark", "") is None
        finally:
            conn.close()

    def test_pick_row_breaks_ties_by_craft_id(self, tmp_path, monkeypatch):
        """При равном crafted_at решает второй ключ ORDER BY — craft_id.

        Две копии «Искры» вставлены в порядке c3, затем c1 при ОДНАКОВОМ
        crafted_at, поэтому детерминированный ответ — c1. Краснеет на
        тай-брейке `craft_id DESC` (→ c3). Мутант «второго ключа нет»
        (ORDER BY crafted_at) тоже краснеет — вопреки ожиданию: план запроса
        `SEARCH ... USING INDEX ix_sigil_crafts_card` + temp B-TREE, то есть
        при равенстве crafted_at строки приходят в порядке вставки (rowid), а
        не по возрастанию craft_id, и первой выходит c3. На это полагаться
        нельзя (sqlite порядок равенства не обещает), поэтому контракт теста —
        направление тай-брейка, а сам второй ключ нужен Task 4 («11-е действие
        → 409», «карта ушла») как единственный детерминированный выбор.
        """
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [
            ("c3", "spark", "Искра третья", "2026-01-01T00:00:00"),
            ("c1", "spark", "Искра первая", "2026-01-01T00:00:00"),
        ])
        conn = srv.get_db()
        try:
            assert srv._trade_pick_row(conn, "dev-a", "spark", "")["craft_id"] == "c1"
        finally:
            conn.close()

    def test_pick_row_chromatic_only_that_instance(self, tmp_path, monkeypatch):
        """Хроматик — ровно этот craft_id ровно этого владельца.

        Экземпляры разных владельцев различаются идентификаторами (x1 у dev-a,
        x2 у dev-b), иначе оба утверждения о чужом экземпляре проходили бы и
        без `device_id = ?`: при одинаковых литералах съеденный binding
        ничего не меняет в ответе.
        """
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [("x1", "", "Хроматик", "2026-01-01T00:00:00")])
        _seed(srv, "dev-b", [("x2", "", "Чужой хроматик", "2026-01-01T00:00:00")])
        conn = srv.get_db()
        try:
            assert srv._trade_pick_row(conn, "dev-a", "", "x1")["craft_id"] == "x1"
            assert srv._trade_pick_row(conn, "dev-a", "", "x2") is None
            assert srv._trade_pick_row(conn, "dev-b", "", "x1") is None
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
        # нормализация пробела: `("spark", "   ")` — это карта по виду, а не
        # пара селекторов; без `.strip()` на craft_id в SQL ушёл бы непустой
        # «хроматик» из пробелов, и аналогично для card_id слева.
        assert srv._trade_selector("spark", "   ") == ("spark", "")
        assert srv._trade_selector("  ", "x1") == ("", "x1")
        for bad in (("spark", "x1"), ("", ""), ("  ", " ")):
            try:
                srv._trade_selector(bad[0], bad[1])
                assert False, bad
            except HTTPException as e:
                assert (e.status_code, e.detail) == (422, "bad_selector"), bad

    def test_week_counter_is_per_device_and_week(self, tmp_path, monkeypatch):
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
            # без `device_id = ?` в SELECT счётчик dev-a показался бы и для
            # dev-b — недельный лимит перестал бы быть персональным.
            assert srv._trade_week_count(conn, "2026-W43", "dev-b") == 0
        finally:
            conn.close()

    def test_ttl_cutoff_is_exactly_trade_ttl_days(self, tmp_path, monkeypatch):
        """Cutoff = РОВНО TRADE_TTL_DAYS суток назад.

        Голый `assert cutoff < _now_iso()` красным не бывает никогда: именно
        им старый тест проверял TTL и пропускал timedelta(days=400).
        """
        srv = _srv(tmp_path, monkeypatch)
        cutoff = srv._trade_ttl_cutoff()
        age_sec = (srv._now_dt() - datetime.fromisoformat(cutoff)).total_seconds()
        assert abs(age_sec - srv.TRADE_TTL_DAYS * 86400) < 2
        assert cutoff < srv._now_iso()

    def test_open_count_counts_only_my_fresh_pending(self, tmp_path, monkeypatch):
        """Квота TRADE_OPEN_MAX — только мои свежие pending (§7.1).

        Каждое утверждение снимает ровно одно условие запроса
        `_trade_open_count`: без `state = 'pending'` в квоту лезут accepted и
        cancelled, без `created_at >= cutoff` — просроченные, без
        `maker_device = ?` — чужие офферы, где я taker. Граница
        `created_at == cutoff` считается активной, то есть оператор `>=`, а
        не `>`. `_trade_ttl_cutoff` заморожен monkeypatch: он монотонно
        «уезжает» вперёд между вызовами, и проверка границы зависела бы от
        тайминга прогона.
        """
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        cutoff = srv._trade_ttl_cutoff()
        monkeypatch.setattr(srv, "_trade_ttl_cutoff", lambda: cutoff)
        now = srv._now_iso()
        stale = (datetime.fromisoformat(cutoff) - timedelta(days=1)).isoformat()
        conn = srv.get_db()
        try:
            _order(srv, "dev-a", "dev-b", "pending", now)
            assert srv._trade_open_count(conn, "dev-a") == 1, "свежий pending"
            _order(srv, "dev-a", "dev-b", "pending", stale)
            assert srv._trade_open_count(conn, "dev-a") == 1, "просроченный pending"
            _order(srv, "dev-a", "dev-b", "accepted", now)
            assert srv._trade_open_count(conn, "dev-a") == 1, "accepted"
            _order(srv, "dev-a", "dev-b", "cancelled", now)
            assert srv._trade_open_count(conn, "dev-a") == 1, "cancelled"
            _order(srv, "dev-c", "dev-a", "pending", now)
            assert srv._trade_open_count(conn, "dev-a") == 1, "я taker, не maker"
            _order(srv, "dev-d", "dev-b", "pending", cutoff)
            assert srv._trade_open_count(conn, "dev-d") == 1, "граница cutoff (>=)"
        finally:
            conn.close()

    def test_name_map_returns_exactly_requested_pairs(self, tmp_path, monkeypatch):
        """`_trade_name_map` отдаёт ровно запрошенные пары (спека §5.1).

        dev-a владеет x1 и x2, dev-b владеет только x1. Запрос
        {("dev-a","x1"), ("dev-b","x1"), ("dev-b","x2")} обязан дать РОВНО два
        ключа и не дать ("dev-a","x2"): список владельцев и список id берутся
        раздельно, поэтому два IN — декартовы, и без сверки пары мутантом
        `name-map-pair-filter` чужая строка x2 утекает в ответ целиком. Третья
        пара («просят имя у того, кто её не держит») нужна именно затем, чтобы
        утечка проявилась: на двух корректных парах лишний ключ физически не
        откуда.
        """
        srv = _srv(tmp_path, monkeypatch)
        _client(srv)
        _seed(srv, "dev-a", [
            ("x1", "", "Хроматик", "2026-01-01T00:00:00"),
            ("x2", "", "Второй хроматик", "2026-01-01T00:00:00"),
        ])
        _seed(srv, "dev-b", [("x1", "", "Чужой хроматик", "2026-01-01T00:00:00")])
        conn = srv.get_db()
        try:
            got = srv._trade_name_map(conn, {
                ("dev-a", "x1"), ("dev-b", "x1"), ("dev-b", "x2")})
            assert got == {("dev-a", "x1"): "Хроматик",
                           ("dev-b", "x1"): "Чужой хроматик"}, got
            assert ("dev-a", "x2") not in got
        finally:
            conn.close()
