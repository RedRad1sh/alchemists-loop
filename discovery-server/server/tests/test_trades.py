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

TRADE_TABLES = ("trade_orders", "trade_counts", "trade_items")


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
    """Строка trade_orders + позиции trade_items в обход ручки (её не будет до
    Task 3). created_at — ISO. give=spark / want=ice — прежние литералы S2.
    """
    conn = sqlite3.connect(s.DB_PATH)
    cur = conn.execute(
        "INSERT INTO trade_orders (maker_device, taker_device, state,"
        " created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        (maker, taker, state, created_at, created_at))
    oid = cur.lastrowid
    conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                 " VALUES (?, 'give', 'spark', '', 0)", (oid,))
    conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                 " VALUES (?, 'want', 'ice', '', 0)", (oid,))
    conn.commit()
    conn.close()


import json

TRADE_CARDS = ["spark", "coal", "ember", "ice", "stone"]

TRADE_CATALOG = {
    "version": "0123456789abcdef",
    "generated_at": "2026-10-21T00:00:00Z",
    "sets": [{"id": "fire", "title": "Стихия Огня",
              "card_ids": ["spark", "coal", "ember"]}],
    "cards": [],
}
for _i, _cid in enumerate(TRADE_CARDS):
    TRADE_CATALOG["cards"].append({
        "id": _cid, "set": "fire" if _cid in ("spark", "coal", "ember") else "water",
        "rarity": "common", "recipe": [{"item_id": "fire", "qty": 10}],
        "ether_cost": 40, "process": "процесс", "stage": "nigredo",
        "fallback_name": _cid.capitalize(), "object_type": "object",
        "seed": 10 + _i,
    })


def _trade_client(s, tmp_path, monkeypatch):
    """Клиент с подменённым каталогом: want_card_id проверяется по нему (§7.1)."""
    path = tmp_path / "trade_catalog.json"
    path.write_text(json.dumps(TRADE_CATALOG, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(s, "SIGIL_CATALOG_PATH", str(path))
    s._sigil_catalog_cache_clear()
    return _client(s)


def _friends(client, a="dev-a", b="dev-b"):
    """A ↔ B друзья — через контрактные ручки S1, не прямым INSERT'ом."""
    _player(client, "Аня", a)
    _player(client, "Николя", b)
    r = client.post("/api/friend/request",
                    json={"device_id": a, "target_nick": "Николя"})
    assert r.status_code == 200, r.text
    r = client.post("/api/friend/respond",
                    json={"device_id": b, "requester_device": a, "accept": True})
    assert r.status_code == 200, r.text


def _offer(client, device_id, to, give=None, want=None):
    """Списочная форма NM §2.2: give/want — списки Item ({card_id} | {craft_id}).
    Дефолты — прежние литералы S2 (spark ↔ ice), половина сюиты строит «обычный»
    оффер без параметров."""
    return client.post("/api/trade/offer", json={
        "device_id": device_id, "to": to,
        "give": [{"card_id": "spark"}] if give is None else give,
        "want": [{"card_id": "ice"}] if want is None else want})


def _items_of(s, oid):
    """Позиции оффера в хранилище: (side, card_id, craft_id, pos) по порядку."""
    return _rows(s, "SELECT side, card_id, craft_id, pos FROM trade_items"
                    " WHERE order_id = ? ORDER BY side, pos", (oid,))


def _rows(s, sql, args=()):
    conn = sqlite3.connect(s.DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(sql, args).fetchall()]
    finally:
        conn.close()


def _owners(s):
    return {r["craft_id"]: r["device_id"] for r in
            _rows(s, "SELECT craft_id, device_id FROM sigil_crafts")}


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
        """Свежая БД (init_db) и живая (003_trades.sql + 004_trade_items.sql +
        heal-шаг) совпадают.

        Дублирование DDL — действующая конвенция (001_social.sql / 002_*.sql):
        без этого копии schema.sql и миграции разъезжаются молча, а живую БД
        правка schema.sql не касается вовсе. С Task 1 одного 003 мало: он
        создаёт trade_orders СО старыми колонками, а свежая схема — уже без
        них, поэтому bare-БД прогоняется и через `_migrate_trade_items` (тот
        же шаг, что в init_db).
        """
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            reference = {t: _columns(conn, t) for t in TRADE_TABLES}
            ref_idx = {t: _indexes(conn, t) for t in TRADE_TABLES}
            # Табличный CHECK (side IN ('give','want')) в PRAGMA table_info /
            # index_xinfo не виден вовсе, поэтому drift между двумя копиями
            # DDL ловится только текстом из sqlite_master.
            ref_ddl = {t: conn.execute(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                (t,)).fetchone()[0] for t in TRADE_TABLES}
        finally:
            conn.close()

        bare_path = str(tmp_path / "bare.db")
        bare = sqlite3.connect(bare_path)
        bare.row_factory = sqlite3.Row
        for mig in ("003_trades.sql", "004_trade_items.sql"):
            mig_path = os.path.join(SERVER_DIR, "migrations", mig)
            assert os.path.exists(mig_path), mig_path
            with open(mig_path, "r", encoding="utf-8") as f:
                bare.executescript(f.read())
        # heal как на живой БД при апгрейде: колонок нет, строки переехали
        srv._migrate_trade_items(bare)
        try:
            for t in TRADE_TABLES:
                assert _columns(bare, t) == reference[t], t
                assert _indexes(bare, t) == ref_idx[t], t
                assert bare.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                    (t,)).fetchone()[0] == ref_ddl[t], t
            # Опорный ассерт: равенство текстов гарантирует наличие CHECK в
            # обеих копиях только если CHECK есть хотя бы в одной из них.
            assert "CHECK (side IN ('give', 'want'))" in ref_ddl["trade_items"]
        finally:
            bare.close()

    def test_init_db_twice_registers_versions_three_and_four(self, tmp_path, monkeypatch):
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
        # Без 004 в реестре trade_items на живой БД не появляется: CREATE в
        # теле миграции — единственный путь для неё (схема свежа уже с
        # таблицей), а parity-тест выше дрейфа не видит.
        assert "004_trade_items.sql" in names, names
        assert {int(r["version"]) for r in rows if r["name"] == "004_trade_items.sql"} == {4}, rows
        assert len(names) == len(set(names)), ("миграция применена дважды", names)


class TestMigration004:
    """NM §2.1: одиночные колонки trade_orders → таблица позиций trade_items."""

    def test_migration_004_heals_s2_rows_and_drops_columns(self, tmp_path, monkeypatch):
        """Живая S2-БД: старые строки становятся позициями, колонки уходят.

        Старая форма собирается из 003_trades.sql — ровно то, что живая БД
        получила на S2, — и дополняется строками старого формата прямым
        INSERT'ом: ручка offer к этой задаче уже ничего не гарантирует (её
        переписывает Task 2), а heal проверяется на данных, а не на коде.
        Почему heal — Python-шаг init_db, а не тело 004: docstring
        `_migrate_trade_items`.
        """
        srv = _srv(tmp_path, monkeypatch)
        mig003 = os.path.join(SERVER_DIR, "migrations", "003_trades.sql")
        assert os.path.exists(mig003), mig003
        with open(mig003, "r", encoding="utf-8") as f:
            ddl = f.read()
        conn = sqlite3.connect(srv.DB_PATH)
        conn.executescript(ddl)
        conn.execute(
            "INSERT INTO trade_orders (maker_device, taker_device, give_card_id,"
            " want_craft_id, state, created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
            ("dev-a", "dev-b", "clay", "c-09", "pending", "t", "t"))
        conn.execute(
            "INSERT INTO trade_orders (maker_device, taker_device, give_craft_id,"
            " state, created_at, updated_at) VALUES (?,?,?,?,?,?)",
            ("dev-c", "dev-d", "c-31", "accepted", "t", "t"))
        conn.commit()
        conn.close()

        srv.init_db()  # schema.sql + _apply_migrations (004) + heal-шаг

        healed = [(r["order_id"], r["side"], r["card_id"], r["craft_id"], r["pos"])
                  for r in _rows(srv, "SELECT order_id, side, card_id, craft_id, pos"
                                      " FROM trade_items ORDER BY order_id, side")]
        assert healed == [
            (1, "give", "clay", "", 0), (1, "want", "", "c-09", 0),
            (2, "give", "", "c-31", 0)], healed
        cols = {r["name"] for r in _rows(srv, "PRAGMA table_info(trade_orders)")}
        assert cols & {"give_card_id", "give_craft_id",
                       "want_card_id", "want_craft_id"} == set(), cols
        # Идемпотентность: второй init_db не падает и не дублирует позиции
        # (после DROP PRAGMA-guard уже ложен).
        srv.init_db()
        assert [(r["order_id"], r["side"], r["card_id"], r["craft_id"], r["pos"])
                for r in _rows(srv, "SELECT order_id, side, card_id, craft_id, pos"
                                    " FROM trade_items ORDER BY order_id, side")] == healed
        # DROP COLUMN требует sqlite >= 3.35 — пин версии движка.
        assert sqlite3.sqlite_version_info >= (3, 35)

    def test_migration_004_heals_partial_pair_without_data_loss(self, tmp_path, monkeypatch):
        """Регресс на асимметричный guard: таблица с ОДНОЙ колонкой пары give_*.

        В e16ae5d копирование было ключено по наличию ПАРЫ ({"give_card_id",
        "give_craft_id"} <= tcols), а DROP — на пересечении одиночных колонок.
        Итог: give_card_id без give_craft_id удалялась без INSERT…SELECT, то
        есть строка теряла позицию молча и инвариант «каждая pre-existing
        S2-строка = одна give-позиция и одна want-позиция» нарушался.
        """
        srv = _srv(tmp_path, monkeypatch)
        conn = sqlite3.connect(srv.DB_PATH)
        conn.executescript(
            "CREATE TABLE trade_orders ("
            "    id             INTEGER PRIMARY KEY AUTOINCREMENT,"
            "    maker_device   TEXT NOT NULL,"
            "    taker_device   TEXT NOT NULL,"
            "    give_card_id   TEXT NOT NULL DEFAULT '',"
            "    state          TEXT NOT NULL DEFAULT 'pending',"
            "    created_at     TEXT NOT NULL,"
            "    updated_at     TEXT NOT NULL);"
        )
        conn.execute("INSERT INTO trade_orders (maker_device, taker_device,"
                     " give_card_id, state, created_at, updated_at)"
                     " VALUES ('dev-a', 'dev-b', 'clay', 'pending', 't', 't')")
        conn.commit()
        conn.close()

        srv.init_db()  # schema.sql + _apply_migrations (004) + heal-шаг

        assert [(r["order_id"], r["side"], r["card_id"], r["craft_id"], r["pos"])
                for r in _rows(srv, "SELECT order_id, side, card_id, craft_id, pos"
                                    " FROM trade_items ORDER BY order_id, side")] == \
            [(1, "give", "clay", "", 0)], "позиция потеряна при heal"
        cols = {r["name"] for r in _rows(srv, "PRAGMA table_info(trade_orders)")}
        assert cols & {"give_card_id", "give_craft_id",
                       "want_card_id", "want_craft_id"} == set(), cols

    def test_migration_004_heal_skips_legacy_row_without_selectors(self, tmp_path, monkeypatch):
        """Пустая S2-строка (все четыре колонки '') не рождает позиций.

        Пинует `WHERE <col> != ''` в heal: без предиката в trade_items
        легли бы пустые позиции (по одной на колонку), и accept прочитал бы их
        как настоящие карты.
        """
        srv = _srv(tmp_path, monkeypatch)
        mig003 = os.path.join(SERVER_DIR, "migrations", "003_trades.sql")
        with open(mig003, "r", encoding="utf-8") as f:
            conn = sqlite3.connect(srv.DB_PATH)
            conn.executescript(f.read())
            conn.execute("INSERT INTO trade_orders (maker_device, taker_device,"
                         " state, created_at, updated_at)"
                         " VALUES ('dev-a', 'dev-b', 'pending', 't', 't')")
            conn.commit()
            conn.close()

        srv.init_db()

        assert _rows(srv, "SELECT * FROM trade_items") == []
        cols = {r["name"] for r in _rows(srv, "PRAGMA table_info(trade_orders)")}
        assert cols & {"give_card_id", "give_craft_id",
                       "want_card_id", "want_craft_id"} == set(), cols
        # строка оффера при этом жива: heal переносит позиции, а не офферы
        assert len(_rows(srv, "SELECT id FROM trade_orders")) == 1


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


class TestOffer:
    def test_offer_creates_one_pending_row(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _offer(client, "dev-a", "dev-b")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["ok"] is True and body["id"] > 0 and body["existed"] is False
        rows = _rows(s, "SELECT * FROM trade_orders")
        assert len(rows) == 1 and rows[0]["state"] == "pending"
        assert rows[0]["maker_device"] == "dev-a" and rows[0]["taker_device"] == "dev-b"
        # NM §2.1: позиции живут в trade_items, по одной строке на сторону S2-оффера
        assert _items_of(s, rows[0]["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0},
            {"side": "want", "card_id": "ice", "craft_id": "", "pos": 0}]
        # оффер НЕ переносит карты (§5.0, §7.1) и не тратит лимит
        assert _owners(s)["c1"] == "dev-a"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_duplicate_pending_offer_is_idempotent(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        first = _offer(client, "dev-a", "dev-b").json()
        again = _offer(client, "dev-a", "dev-b")
        assert again.status_code == 200
        body = again.json()
        assert body["existed"] is True and body["id"] == first["id"]
        assert len(_rows(s, "SELECT * FROM trade_orders")) == 1        # §7.1

    def test_expired_pending_is_not_a_duplicate(self, tmp_path, monkeypatch):
        """Дедуп обязан видеть TTL: просроченный pending — не дубль (F1/Q1).

        `_trade_open_count` (§7.1 rule 2) просроченные строки из квоты уже
        выбрасывает — это закреплено тестом
        test_open_count_counts_only_my_fresh_pending, а поиск дубля в этой же
        ручке — нет. Пока условия отличались, на практике недели без ответа
        (`TRADE_TTL_DAYS = 7`) игрок получал `ok:true, existed:true` с id
        строки, которую `GET /api/trade/list` скрывает, а
        `POST /api/trade/accept` отвергает как `expired` (§6.1): повтор той же
        карты тому же другу был невозможен до cancel. Просрочка моделируется
        UPDATE'ом created_at ОТ ЧАСОВ СЕРВЕРА (`s._now_iso()`), а не
        дата-литералом, — иначе кейс краснеет/зеленеет по календарю.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        first = _offer(client, "dev-a", "dev-b").json()
        assert first["existed"] is False, first
        stale = (datetime.fromisoformat(s._now_iso())
                 - timedelta(days=s.TRADE_TTL_DAYS + 1)).isoformat()
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("UPDATE trade_orders SET created_at = ?", (stale,))
        conn.commit()
        conn.close()
        conn = s.get_db()
        try:
            # посылка: строка для квоты уже мертва, иначе «свежий» дубль ниже
            # был бы законным (активный pending, rule 4)
            assert s._trade_open_count(conn, "dev-a") == 0
        finally:
            conn.close()
        again = _offer(client, "dev-a", "dev-b")
        assert again.status_code == 200, again.text
        body = again.json()
        assert body["existed"] is False, ("просроченный pending не дубль", body)
        assert body["id"] != first["id"], body
        rows = _rows(s, "SELECT id, created_at FROM trade_orders"
                        " WHERE state = 'pending' ORDER BY id")
        assert len(rows) == 2, rows                                # + живая строка
        assert rows[0]["created_at"] == stale, rows                # старую не «реанимировали»
        assert rows[1]["id"] == body["id"] and rows[1]["created_at"] > stale, rows

    def test_offer_of_card_not_owned_is_409(self, tmp_path, monkeypatch):
        """Ruling 4 (ledger): S2 `card_not_owned` 422 — это та же проверка
        коллекции в новой модели, коды спеки NM §2.3 дают ей 409 not_enough_copies."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        r = _offer(client, "dev-a", "dev-b")
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert _rows(s, "SELECT * FROM trade_orders") == []            # кейс 15

    def test_offer_rejects_ghost_want_card(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _offer(client, "dev-a", "dev-b", want=[{"card_id": "phantom"}])
        assert (r.status_code, r.json()["detail"]) == (422, "unknown_card")  # кейс 17
        # хроматик в want каталогом не проверяется: экземпляра в каталоге нет,
        # но сверка с коллекцией taker (ruling 1) обязана пройти — x9 у dev-b есть
        _seed(s, "dev-b", [("x9", "", "Радуга", "2026-01-01T00:00:00")])
        assert _offer(client, "dev-a", "dev-b",
                      want=[{"craft_id": "x9"}]).status_code == 200

    def test_offer_side_length_item_form_and_self_deal_codes(self, tmp_path, monkeypatch):
        """NM §2.3 п.2–3: длина стороны — side_too_long, форма элемента — bad_item
        (ruling 1: S2 `bad_selector` в новой модели живёт как `bad_item`)."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _offer(client, "dev-a", "dev-b", give=[], want=[{"card_id": "ice"}])
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "spark", "craft_id": "c1"}], want=[])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")        # кейс 8
        r = _offer(client, "dev-a", "dev-a")
        assert (r.status_code, r.json()["detail"]) == (422, "self_deal")       # кейс 9

    def test_offer_want_side_is_enforced_per_item(self, tmp_path, monkeypatch):
        """Каждая позиция want проверяется (NM §2.3 п.2–5): форма — bad_item,
        пустой want легален (0..TRADE_SIDE_MAX), а прежний инвариант «want обязан
        быть XOR-селектором» переехал в пер-элементную проверку формы: мутант
        «читать it.card_id напрямую, без strip/XOR» краснеет на третьем кейсе
        (пара пробелов), как и на первом (оба поля заполнены)."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        # обе селекторы заполнены: мусорный хроматик «zz» до коллекции не доходит
        r = _offer(client, "dev-a", "dev-b", want=[{"card_id": "ice", "craft_id": "zz"}])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        r = _offer(client, "dev-a", "dev-b", want=[{}])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        # пробелы — это пустота: без .strip() ушла бы «непустая» позиция из пробелов
        r = _offer(client, "dev-a", "dev-b",
                   want=[{"card_id": "  ", "craft_id": " "}])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        # ни одна rejected-ветка не оставила строку, в том числе битую
        assert _rows(s, "SELECT * FROM trade_orders") == []
        # пустой want — законный односторонний оффер (висячий «подарок» без per-копии)
        r = _offer(client, "dev-a", "dev-b", want=[])
        assert r.status_code == 200, r.text
        assert _items_of(s, r.json()["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0}]

    def test_offer_guards_caller_friends_registration(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _player(client, "Аня", "dev-a")
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _offer(client, "dev-a", "dev-z")
        assert (r.status_code, r.json()["detail"]) == (404, "not_registered")
        _player(client, "Варя", "dev-v")
        r = _offer(client, "dev-a", "dev-v")
        assert (r.status_code, r.json()["detail"]) == (404, "not_friends")
        assert _rows(s, "SELECT * FROM trade_orders") == []                   # кейс 5
        r = _offer(client, "npc-spirit", "dev-a")
        assert (r.status_code, r.json()["detail"]) == (400, "npc"), r.text     # кейс 6
        # `_social_id`/`_social_caller` общие с соц-ручками, и там коды названы
        # (test_social.py:669/798/890) — на этом маршруте тоже пинится машинный
        # код, а не только статус: min_length=1 считается по сырой строке,
        # поэтому "   " и "a|b" доходят до хендлера.
        for bad in ("   ", "a|b"):
            r = _offer(client, bad, "dev-a")
            assert (r.status_code, r.json()["detail"]) == (400, "bad_device_id"), (bad, r.text)

    def test_open_offer_cap(self, tmp_path, monkeypatch):
        """21-й активный pending у одного maker → 409 too_many_open (кейс 16).

        Честными офферами набирается только len(TRADE_CARDS) = 5, поэтому остаток
        до потолка добирается прямым INSERT'ом: тест проверяет константу
        TRADE_OPEN_MAX, а не способность каталога исчерпать её честными офферами.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c%d" % i, cid, "N%d" % i, "2026-01-0%dT00:00:00" % (i + 1))
                           for i, cid in enumerate(TRADE_CARDS)])
        # NM: want больше не «бесплатный» — default ice должен быть у taker'а,
        # иначе честные офферы покраснеют peer_lacks раньше, чем дойдут до потолка
        _seed(s, "dev-b", [("c9", "ice", "Лёд", "2026-02-01T00:00:00")])
        for cid in TRADE_CARDS:
            r = _offer(client, "dev-a", "dev-b", give=[{"card_id": cid}])
            assert r.status_code == 200, (cid, r.text)
        dup = _offer(client, "dev-a", "dev-b", give=[{"card_id": "spark"}])
        assert dup.json()["existed"] is True          # дубль потолок не расходует
        conn = sqlite3.connect(s.DB_PATH)
        # created_at — от часов сервера, а не литерал: строки обязаны быть
        # свежими. С жёсткой датой офферы через TRADE_TTL_DAYS суток уходят в
        # просрочку, потолок не набирается, и кейс краснеет по календарю.
        now = s._now_iso()
        for i in range(s.TRADE_OPEN_MAX - len(TRADE_CARDS)):
            cur = conn.execute(
                "INSERT INTO trade_orders (maker_device, taker_device,"
                " state, created_at, updated_at) VALUES (?, ?, 'pending', ?, ?)",
                ("dev-a", "dev-b", now, now))
            # прежние литералы старого формата: give — экземпляр cx%d, want —
            # ice как craft (наполнение потолка, не валидный want)
            conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                         " VALUES (?, 'give', '', ?, 0)", (cur.lastrowid, "cx%d" % i))
            conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                         " VALUES (?, 'want', '', 'ice', 0)", (cur.lastrowid,))
        conn.commit()
        conn.close()
        assert len(_rows(s, "SELECT * FROM trade_orders WHERE state='pending'")) == s.TRADE_OPEN_MAX
        # 21-й оффер намеренно отдаёт карту, уже висящая в pending (все 5 карт
        # израсходованы в цикле): 409 здесь выдаёт только проверка потолка,
        # стоящая ДО дедупликации. Переставить их местами — кейс покраснеет.
        r = _offer(client, "dev-a", "dev-b", give=[{"card_id": "stone"}],
                   want=[{"card_id": "ice"}])
        assert (r.status_code, r.json()["detail"]) == (409, "too_many_open")


class TestOfferNM:
    """NM §2.2–2.3: offer принимает списки позиций и валидирует обе стороны."""

    def test_offer_accepts_two_by_two_and_writes_items(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("x1", "", "Радуга", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00"),
                           ("c3", "stone", "Камень", "2026-01-04T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "spark"}, {"craft_id": "x1"}],
                   want=[{"card_id": "ice"}, {"card_id": "stone"}])
        assert r.status_code == 200, r.text
        # pos — порядок входного списка, стороны лежат раздельно (§2.1)
        assert _items_of(s, r.json()["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0},
            {"side": "give", "card_id": "", "craft_id": "x1", "pos": 1},
            {"side": "want", "card_id": "ice", "craft_id": "", "pos": 0},
            {"side": "want", "card_id": "stone", "craft_id": "", "pos": 1}]
        assert _owners(s) == {"c1": "dev-a", "x1": "dev-a",
                              "c2": "dev-b", "c3": "dev-b"}   # оффер не переносит
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_offer_side_too_long(self, tmp_path, monkeypatch):
        """Длина стороны — п.2 §2.3, она проверяется ДО формы и коллекции:
        семь одинаковых spark — это side_too_long, а не not_enough_copies."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        over = [{"card_id": "spark"}] * (s.TRADE_SIDE_MAX + 1)
        r = _offer(client, "dev-a", "dev-b", give=over, want=[])
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        r = _offer(client, "dev-a", "dev-b", give=[{"card_id": "spark"}], want=over)
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        r = _offer(client, "dev-a", "dev-b", give=[], want=[])
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        # верхняя граница законна по длине — дальше говорит коллекция (1 копия):
        # снявший проверку длины кейс краснеет здесь на side-коде, а не на 200
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "spark"}] * s.TRADE_SIDE_MAX, want=[])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert _rows(s, "SELECT * FROM trade_orders") == []

    def test_offer_bad_item_both_ids(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "spark", "craft_id": "c1"}], want=[])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        r = _offer(client, "dev-a", "dev-b", give=[{"card_id": "spark"}], want=[{}])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        # нормализация пробела унаследована от _trade_selector (S2 §4):
        # «craft_id из пробелов» — это пустой селектор, а не хроматик
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "spark", "craft_id": "   "}], want=[])
        assert r.status_code == 200, r.text

    def test_offer_dup_beyond_copies(self, tmp_path, monkeypatch):
        """Две ячейки одного вида при одной копии — 409 not_enough_copies;
        хроматик в стороне не повторяется (ruling 3)."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "coal", "Уголь", "2026-01-01T00:00:00"),
                           ("x1", "", "Радуга", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "coal"}, {"card_id": "coal"}], want=[])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"craft_id": "x1"}, {"craft_id": "x1"}], want=[])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert _rows(s, "SELECT * FROM trade_orders") == []
        # вторая копия открывает вторую ячейку
        _seed(s, "dev-a", [("c9", "coal", "Уголь второй", "2026-01-04T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "coal"}, {"card_id": "coal"}], want=[])
        assert r.status_code == 200, r.text
        assert _items_of(s, r.json()["id"]) == [
            {"side": "give", "card_id": "coal", "craft_id": "", "pos": 0},
            {"side": "give", "card_id": "coal", "craft_id": "", "pos": 1}]

    def test_offer_peer_lacks(self, tmp_path, monkeypatch):
        """Ruling 1: S2 доказывал наличие want-карты только на accept; в N↔M
        requested позиции обязаны существовать в коллекции taker на момент оффера."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _offer(client, "dev-a", "dev-b", want=[{"card_id": "ice"}])
        assert (r.status_code, r.json()["detail"]) == (409, "peer_lacks")
        # зеркально: своя копия spark не даёт просить spark у друга
        r = _offer(client, "dev-a", "dev-b", want=[{"card_id": "spark"}])
        assert (r.status_code, r.json()["detail"]) == (409, "peer_lacks")
        # хроматик, которого у taker нет, — тоже peer_lacks (каталог его не касается)
        r = _offer(client, "dev-a", "dev-b", want=[{"craft_id": "zz"}])
        assert (r.status_code, r.json()["detail"]) == (409, "peer_lacks")
        # две ячейки одного вида при единственной копии друга
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   want=[{"card_id": "ice"}, {"card_id": "ice"}])
        assert (r.status_code, r.json()["detail"]) == (409, "peer_lacks")
        assert _rows(s, "SELECT * FROM trade_orders") == []
        # одна копия, одна ячейка — законно
        r = _offer(client, "dev-a", "dev-b", want=[{"card_id": "ice"}])
        assert r.status_code == 200, r.text

    def test_offer_duplicate_keys_on_give_multiset(self, tmp_path, monkeypatch):
        """Ruling 5: дубль = равные give-мультимножества; changed want возвращает
        существующую строку (семантика S2 §7.1 rule 4), порядок give не важен."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c4", "coal", "Уголь", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00"),
                           ("c3", "stone", "Камень", "2026-01-04T00:00:00")])
        first = _offer(client, "dev-a", "dev-b",
                       give=[{"card_id": "spark"}, {"card_id": "coal"}],
                       want=[{"card_id": "ice"}]).json()
        assert first["existed"] is False, first
        # тот же give-мультимножество в обратном порядке и с другим want — дубль
        again = _offer(client, "dev-a", "dev-b",
                       give=[{"card_id": "coal"}, {"card_id": "spark"}],
                       want=[{"card_id": "stone"}])
        assert again.status_code == 200, again.text
        body = again.json()
        assert body["existed"] is True and body["id"] == first["id"], body
        rows = _rows(s, "SELECT * FROM trade_orders")
        assert len(rows) == 1, rows
        # существующая строка сохранила исходные позиции (не перезаписана)
        assert _items_of(s, rows[0]["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0},
            {"side": "give", "card_id": "coal", "craft_id": "", "pos": 1},
            {"side": "want", "card_id": "ice", "craft_id": "", "pos": 0}]

    def test_offer_give_multiset_change_is_a_new_row(self, tmp_path, monkeypatch):
        """Не равное give-мультимножество — это новый оффер, а не existed."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c8", "spark", "Искра вторая", "2026-01-02T00:00:00")])
        first = _offer(client, "dev-a", "dev-b",
                       give=[{"card_id": "spark"}], want=[]).json()
        second = _offer(client, "dev-a", "dev-b",
                        give=[{"card_id": "spark"}, {"card_id": "spark"}], want=[])
        assert second.status_code == 200, second.text
        body = second.json()
        assert body["existed"] is False and body["id"] != first["id"], body
        assert len(_rows(s, "SELECT * FROM trade_orders")) == 2

    def test_offer_compound_deficit_plus_overlong_want_is_side_too_long(
            self, tmp_path, monkeypatch):
        """§2.3: стадии ГЛОБАЛЬНЫЕ — длина обеих сторон (п.2) проверяется до
        коллекции give (п.4). Композитное нарушение «дефицит в give + want
        длиннее TRADE_SIDE_MAX» обязано ответить 422 side_too_long, а не 409
        not_enough_copies: переставить стороны местами в валидаторе — и этот
        тест краснеет на 409."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "coal", "Уголь", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "coal"}, {"card_id": "coal"}],  # дефицит: 1 копия
                   want=[{"card_id": "ice"}] * (s.TRADE_SIDE_MAX + 1))
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        assert _rows(s, "SELECT * FROM trade_orders") == []

    def test_offer_want_bad_item_form_beats_give_deficit(self, tmp_path, monkeypatch):
        """§2.3 п.3 до п.4: форма элементов обеих сторон проверяется до коллекций.
        Битая форма в want (оба id) при законном дефиците в give — 422 bad_item,
        а не 409 not_enough_copies."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "coal", "Уголь", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _offer(client, "dev-a", "dev-b",
                   give=[{"card_id": "coal"}, {"card_id": "coal"}],  # дефицит: 1 копия
                   want=[{"card_id": "ice", "craft_id": "c2"}])      # XOR нарушен
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")
        assert _rows(s, "SELECT * FROM trade_orders") == []


def _both(s):
    """По карте у каждого: dev-a отдаёт spark, dev-b отдаёт ice."""
    _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
    _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])


def _accept(client, device_id, order_id):
    return client.post("/api/trade/accept",
                       json={"device_id": device_id, "id": order_id})


def _fill_week(s, devices, count=10):
    conn = sqlite3.connect(s.DB_PATH)
    for dev in devices:
        conn.execute("INSERT INTO trade_counts (week, device_id, count)"
                     " VALUES (?, ?, ?)", (s._week_key(), dev, count))
    conn.commit()
    conn.close()


def _stale_iso(s):
    """created_at заведомо старше TTL **по часам сервера**.

    Дата-литерал («2026-01-01») проверял бы не правило TTL, а календарь прогона:
    он остаётся в прошлом при любом TRADE_TTL_DAYS, поэтому при подъёме константы
    (например до 300 суток) строка перестала бы быть просроченной и кейс
    покраснел бы из-за законной смены настройки. Здесь возраст выведен из
    `s._now_iso()` и из самой константы, поэтому премиса «строка старше cutoff»
    проверяема (её ассертует вызывающий тест), а не предполагается. Тот же идиом
    уже закреплён в test_expired_pending_is_not_a_duplicate.
    """
    return (datetime.fromisoformat(s._now_iso())
            - timedelta(days=s.TRADE_TTL_DAYS + 1)).isoformat()


class TestAccept:
    def test_swap_moves_rows_and_counts(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _accept(client, "dev-b", oid)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["moved_in"] == {"craft_id": "c1", "card_id": "spark",
                                    "llm_name": "Искра"}, body
        assert body["moved_out"] == {"craft_id": "c2", "card_id": "ice",
                                     "llm_name": "Лёд"}, body
        assert _owners(s) == {"c1": "dev-b", "c2": "dev-a"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "accepted"
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 1}, counts
        assert body["remain"] == 9 and body["peer_remain"] == 9   # §7: число серверное

    def test_double_accept_is_not_found(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        assert _accept(client, "dev-b", oid).status_code == 200
        again = _accept(client, "dev-b", oid)
        assert (again.status_code, again.json()["detail"]) == (404, "not_found")  # 3b
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 1}, counts        # ровно один перенос
        # maker не может принять свой же оффер (шаг 1: taker_device != me).
        # Отдельный оффер, а не повтор spark: дубль вернул бы тот же id.
        # want=[] (NM §2.2): после первого обмена ice лежит у maker'а, и
        # дефолтный want=[ice] краснел бы в peer_lacks ещё на offer — а тест
        # ровно про очерёдность accept-проверок, asserted-строки не тронуты.
        _seed(s, "dev-a", [("c3", "coal", "Уголь", "2026-01-03T00:00:00")])
        oid2 = _offer(client, "dev-a", "dev-b", give=[{"card_id": "coal"}],
                      want=[]).json()["id"]
        r = _accept(client, "dev-a", oid2)
        assert (r.status_code, r.json()["detail"]) == (404, "not_found")

    def test_id_out_of_sqlite_range_is_not_found(self, tmp_path, monkeypatch):
        """`id` вне int64 и `id <= 0` — это «оффера нет», а не 500 и не 422 (§7).

        `TradeIdPayload.id` — неограниченный int (pydantic 2.5 принимает и
        10**30), а bind значения вне SQLite INTEGER бросает OverflowError из
        sqlite3: без границы такой запрос падал бы в `except Exception` и
        отдавал 500 вместо машинного кода. Ноль и минус SELECT отвергает и сам,
        они здесь закрепляют, что «несуществующий id» не различает два разных
        способа несуществования.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        for bad in (0, -1, 2 ** 63, 10 ** 30):
            r = _accept(client, "dev-b", bad)
            assert (r.status_code, r.json()["detail"]) == (404, "not_found"), bad
        assert _rows(s, "SELECT id FROM trade_orders")[0]["id"] == oid
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_maker_card_gone_leaves_everything_untouched(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        conn = sqlite3.connect(s.DB_PATH)          # maker «съел» карту в эфир
        conn.execute("DELETE FROM sigil_crafts WHERE device_id='dev-a' AND craft_id='c1'")
        conn.commit()
        conn.close()
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:maker")   # кейс 3
        assert _owners(s) == {"c2": "dev-b"}, "у taker тоже ничего не ушло"
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_taker_card_gone_is_symmetric(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("DELETE FROM sigil_crafts WHERE device_id='dev-b' AND craft_id='c2'")
        conn.commit()
        conn.close()
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:taker")   # 3a
        assert _owners(s) == {"c1": "dev-a"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_week_limit_blocks_eleventh_action(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _fill_week(s, ("dev-a", "dev-b"))
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "week_limit")         # кейс 4
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 10, "dev-b": 10}, counts
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        # «оффер + отмена лимит не тратят» (кейс 4a) доказывается целиком в Task 5 —
        # там же, где появляется `/api/trade/cancel` (`test_offer_and_cancel_do_not_spend_limit`
        # в `TestCancelGift`): здесь проверять нечего, отменять ещё нечего.

    def test_expired_offer_is_409(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        stale = _stale_iso(s)
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("UPDATE trade_orders SET created_at = ? WHERE id = ?",
                     (stale, oid))
        conn.commit()
        conn.close()
        # премиса, а не удача по календарю: строка старше cutoff по тем же
        # часам, из которых считается `_trade_ttl_cutoff()`.
        assert stale < s._trade_ttl_cutoff(), (stale, s._trade_ttl_cutoff())
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "expired")            # кейс 11
        assert _rows(s, "SELECT * FROM trade_counts") == []
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"

    def test_chromatic_swap_moves_exactly_that_instance(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("x1", "", "Радуга", "2026-01-01T00:00:00"),
                           ("p1", "spark", "Искра", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b", give=[{"craft_id": "x1"}]).json()["id"]
        body = _accept(client, "dev-b", oid).json()
        assert body["moved_in"]["craft_id"] == "x1", body
        assert _owners(s) == {"x1": "dev-b", "p1": "dev-a", "c2": "dev-a"}

    def test_foreign_craft_id_in_want_dies_at_accept(self, tmp_path, monkeypatch):
        """Чужой экземпляр в want-позиции (бывший want_craft_id).

        Выставить такой оффер через /offer нельзя (у taker его нет), но строка
        в БД — намерение, а device_id ничем не аутентифицирован (§10.1), поэтому
        accept обязан держаться за факт владения, а не за историю создания.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _seed(s, "dev-c", [("x2", "", "Спектр", "2026-01-04T00:00:00")])
        conn = sqlite3.connect(s.DB_PATH)
        cur = conn.execute("INSERT INTO trade_orders (maker_device, taker_device,"
                           " state, created_at, updated_at)"
                           " VALUES ('dev-a', 'dev-b', 'pending', ?, ?)",
                           (s._now_iso(), s._now_iso()))
        # прежняя пара селекторов: give — карта spark, want — чужой экземпляр x2
        conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                     " VALUES (?, 'give', 'spark', '', 0)", (cur.lastrowid,))
        conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                     " VALUES (?, 'want', '', 'x2', 0)", (cur.lastrowid,))
        conn.commit()
        conn.close()
        oid = _rows(s, "SELECT id FROM trade_orders")[0]["id"]
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:taker")   # кейс 7
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b", "x2": "dev-c"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_not_friends_at_accept_time(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = client.post("/api/friend/remove",
                        json={"device_id": "dev-b", "peer_device": "dev-a"})
        assert r.status_code == 200, r.text
        acc = _accept(client, "dev-b", oid)
        assert (acc.status_code, acc.json()["detail"]) == (404, "not_friends")
        assert _rows(s, "SELECT * FROM trade_counts") == []
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"

    def test_last_copy_trades_freely(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-02T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        assert _accept(client, "dev-b", oid).status_code == 200                   # кейс 12
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-a"}).json()
        assert "spark" not in coll["cards"] and coll["cards"]["ice"]["copies"] == 1

    def test_shared_craft_id_of_two_players_is_rejected_before_first_write(
            self, tmp_path, monkeypatch):
        """Одинаковый craft_id у двух игроков — это 409 card_gone:taker, а не 500.

        `craft_id = f"{day}_{device_id[:8]}_{index}"` (`grep -n 'device_id\\[:8\\]'
        server.py`: каталог и хроматик строятся в двух местах) берёт только ПЕРВЫЕ 8 символов
        клиентского и не аутентифицированного `device_id`, а ключ у sigil_crafts
        — пара `(device_id, craft_id)` (server.py:1332-1338). Значит два
        аккаунта, заведённых одним клиентом через POST /api/me, законно владеют
        строками с ОДИНАКОВЫМ craft_id, и перенос такой строки UPDATE'ом №6
        попадает в занятый PK: `sqlite3.IntegrityError` → 500 без машинного кода,
        чего §7 не допускает.

        Достижимость — проверяемый факт, а не предположение, поэтому весь путь
        идёт через публичные ручки: /api/me + дружба, /api/sigil/daily +
        /api/sigil/craft в ОДИН слот одного дня обоим, /api/trade/offer,
        /api/trade/accept. Перебор `device_id` (приватный `_generate_sigil_daily`
        ничего не пишет в БД) лишь решает, какими id зарегистрироваться, чтобы
        в одном слоте у maker'а оказался хроматик (его можно отдать по
        craft_id), а у taker'а — каталожная карта (её можно попросить по
        card_id).

        Код — `card_gone:taker`, а не `:maker`: занятой PK виден на первой
        проверке, `(me, give_craft)`, потому что строка taker'а с этим craft_id
        стоит на своём месте. Отказ обязан остаться до первого UPDATE: обе
        строки у своих владельцев, state = pending, trade_counts пуст.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        day = s._now_dt().date().isoformat()
        prefix = "chroma00"            # ровно 8 символов id попадают в craft_id

        maker, slot = None, None
        for k in range(1, 20000):
            d = "%s_%d" % (prefix, k)
            chrom = [i for i, c in enumerate(s._generate_sigil_daily(d, day, set()))
                     if c["is_chromatic"]]
            if chrom:
                maker, slot = d, chrom[0]
                break
        assert maker, "не найден device_id с хроматиком в оффере дня"

        taker, taker_card = None, None
        for k in range(1, 20000):
            d = "%s_%d" % (prefix, k)
            if d == maker:
                continue
            c = s._generate_sigil_daily(d, day, set())[slot]
            if not c["is_chromatic"] and c["card_id"]:
                taker, taker_card = d, c["card_id"]
                break
        assert taker, "не найден taker с каталожной картой в том же слоте"

        _friends(client, maker, taker)

        ids = {}
        for dev in (maker, taker):
            daily = client.get("/api/sigil/daily", params={"device_id": dev}).json()
            cid = daily["crafts"][slot]["id"]
            cr = client.post("/api/sigil/craft",
                             json={"device_id": dev, "craft_id": cid})
            assert cr.status_code == 200 and cr.json()["ok"] is True, cr.text
            ids[dev] = cid
        assert ids[maker] == ids[taker], ids              # тот самый коллидирующий id
        shared = ids[maker]

        oid = _offer(client, maker, taker, give=[{"craft_id": shared}],
                     want=[{"card_id": taker_card}]).json()["id"]
        r = _accept(client, taker, oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:taker"), r.text
        # _owners здесь слеп (два одинаковых ключа), поэтому сверяются кортежи.
        assert {(x["device_id"], x["craft_id"], x["card_id"]) for x in _rows(
            s, "SELECT device_id, craft_id, card_id FROM sigil_crafts")} == {
            (maker, shared, ""), (taker, shared, taker_card)}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_maker_side_collision_is_pinned_by_second_probe(self, tmp_path,
                                                             monkeypatch):
        """Второй проб `(maker, want_craft)` достижим отдельно, и без него — 500.

        Первый проб ловит занятость PK `(me, give_craft)`. Коллизия на
        `(maker, want_craft)` требует ДРУГОГО входа: у maker'а два слота одного
        дня, у taker'а — только тот слот, что дублируется. Тогда PK
        `(me, give_craft)` у taker'а свободен (первый проб молчит), а want_craft
        уже принадлежит maker'у, и UPDATE №7 приезжает на занятый PK.
        Проверено мутацией: с
        удалённой второй проверкой этот путь даёт
        `sqlite3.IntegrityError: UNIQUE constraint failed:
        sigil_crafts.device_id, sigil_crafts.craft_id` → 500 без машинного кода,
        чего §7 не допускает, а остальные тесты остаются зелёными.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        day = s._now_dt().date().isoformat()
        prefix = "chroma00"

        maker, give_i, want_i = None, None, None
        for k in range(1, 40000):
            d = "%s_%d" % (prefix, k)
            cs = s._generate_sigil_daily(d, day, set())
            chrom = [i for i, c in enumerate(cs) if c["is_chromatic"]]
            cat = [i for i, c in enumerate(cs)
                   if not c["is_chromatic"] and c["card_id"]]
            if chrom and cat:
                maker, give_i, want_i = d, chrom[0], cat[0]
                break
        assert maker, "нет device_id с хроматиком и каталогом в разных слотах"

        taker, taker_card = None, None
        for k in range(1, 40000):
            d = "%s_%d" % (prefix, k)
            if d == maker:
                continue
            c = s._generate_sigil_daily(d, day, set())[want_i]
            if not c["is_chromatic"] and c["card_id"]:
                taker, taker_card = d, c["card_id"]
                break
        assert taker, "нет taker'а с каталожной картой в коллидирующем слоте"

        _friends(client, maker, taker)
        ids = {}
        for dev, slots in ((maker, (give_i, want_i)), (taker, (want_i,))):
            for slot in slots:
                daily = client.get("/api/sigil/daily",
                                   params={"device_id": dev}).json()
                cid = daily["crafts"][slot]["id"]
                cr = client.post("/api/sigil/craft",
                                 json={"device_id": dev, "craft_id": cid})
                assert cr.status_code == 200 and cr.json()["ok"] is True, cr.text
                ids[(dev, slot)] = cid
        # Оба края коллизии собраны публичным крафтом, без прямых INSERT'ов:
        # один и тот же craft_id у двух игроков, и ни одного лишнего пересечения.
        assert ids[(maker, want_i)] == ids[(taker, want_i)]
        assert ids[(maker, give_i)] != ids[(taker, want_i)]

        oid = _offer(client, maker, taker, give=[{"craft_id": ids[(maker, give_i)]}],
                     want=[{"card_id": taker_card}]).json()["id"]
        r = _accept(client, taker, oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:maker"), r.text
        assert {(x["device_id"], x["craft_id"]) for x in _rows(
            s, "SELECT device_id, craft_id FROM sigil_crafts")} == {
            (maker, ids[(maker, give_i)]), (maker, ids[(maker, want_i)]),
            (taker, ids[(taker, want_i)])}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_accept_without_taker_profile_is_not_registered(self, tmp_path, monkeypatch):
        """`_trade_registered(conn, me)` на accept пинит код, а не декорацию.

        Строка trade_orders переживает удаление аккаунта: `DELETE /api/account`
        (server.py:4188) чистит social и per-device таблицы, а trade_orders и
        trade_counts — нет. Так что «taker без players-строки» собирается честно:
        оффер выставлен, а из players удалён только сам профиль. Ребро дружбы
        при этом на месте, поэтому без проверки регистрации accept дошёл бы до
        переноса и ответил 200 — именно это на тесте и краснеет.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("DELETE FROM players WHERE device_id = 'dev-b'")
        conn.commit()
        conn.close()
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (404, "not_registered"), r.text
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_accept_rejects_reserved_caller_ids(self, tmp_path, monkeypatch):
        """`_social_caller` на accept стоит до БД: зарезервированный id → 400 (§7).

        Без него accept от имени Светика или бота стал бы `404 not_found`
        («оффера нет»), то есть потерял бы машинный код и полез бы SELECT'ом по
        чужому device_id. Пара `id = 10**30` проверяет порядок: проверка формы
        вызывающего обязательна ДО границы id и до `get_db()`, иначе этот вызов
        вернул 404.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        for bad, code in (("npc-spirit", "npc"), ("bot-1", "bot"),
                          ("   ", "bad_device_id"), ("dev-a|dev-b", "bad_device_id")):
            r = _accept(client, bad, oid)
            assert (r.status_code, r.json()["detail"]) == (400, code), (bad, r.text)
        r = _accept(client, "npc-spirit", 10 ** 30)
        assert (r.status_code, r.json()["detail"]) == (400, "npc"), r.text
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_only_maker_at_week_limit_blocks_accept(self, tmp_path, monkeypatch):
        """Недельный лимит считается и у maker'а: 10 у него при пустом taker'е → 409.

        `test_week_limit_blocks_eleventh_action` заполняет ОБА счётчика, поэтому
        цикл `for dev in (me, maker)` можно свести к `(me,)` и прогон останется
        зелёным. Здесь на пределе только maker (dev-a), так что этот мутант
        краснеет ровно на maker-половине ветки.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _fill_week(s, ("dev-a",))                            # только maker = 10
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "week_limit"), r.text
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 10}, counts
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"

    def test_asymmetric_counts_separate_remain_and_peer_remain(self, tmp_path, monkeypatch):
        """remain — счёт принявшего, peer_remain — счёт maker'а (§7).

        Во всех успешных тестах стороны симметричны (по 1 переносу → 9 и 9),
        поэтому перестановка `remain`/`peer_remain` местами не краснит ничего.
        Здесь taker начал неделю с 3 завершённых переносов, maker — с 0: после
        двух `_trade_count_up` это 4 и 1, то есть 6 и 9.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _fill_week(s, ("dev-b",), count=3)                   # taker = 3, maker = 0
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _accept(client, "dev-b", oid)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["remain"] == 6 and body["peer_remain"] == 9, body
        assert _owners(s) == {"c1": "dev-b", "c2": "dev-a"}
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 4}, counts

class TestAcceptNM:
    """Спека §2.4: accept читает позиции из trade_items, перевалидует обе
    стороны по ТЕКУЩИМ коллекциям и переносит все позиции атомарно.
    Дефицит любой позиции — 409 card_gone с S2-суффиксом стороны
    (client-маппинг trade_ui.gd не должен сломаться), ноль переносов,
    state остаётся pending, trade_counts не тронуты."""

    def test_accept_atomic_no_partial_transfer(self, tmp_path, monkeypatch):
        """Сторонний accept снял вторую give-копию maker'а до нашего accept.

        give = [coal, ember] (по одной копии каждого), между оффером и
        принятием maker отдаёт ember стороннему офферу (второй оффер тому же
        taker'у, want пуст — подарочная форма легальна §2.2). Наш accept обязан
        увидеть дефицит на второй give-позиции: 409 card_gone:maker, и НЕ
        сдвинуть первую позицию ни на вершок: coal остаётся у maker'а, ice —
        у taker'а (тот же инвариант, что в S2 `..._leaves_everything_untouched`,
        но мульти-позиционный).
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c3", "coal", "Уголь", "2026-01-01T00:00:00"),
                           ("c4", "ember", "Тлеющий", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "coal"}, {"card_id": "ember"}],
                     want=[{"card_id": "ice"}]).json()["id"]
        oid2 = _offer(client, "dev-a", "dev-b",
                      give=[{"card_id": "ember"}], want=[]).json()["id"]
        assert _accept(client, "dev-b", oid2).status_code == 200
        before = _owners(s)
        assert before["c4"] == "dev-b", "сторонний accept унёс ember"
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:maker")
        assert _owners(s) == before, "ни одна позиция не сдвинута"
        assert before["c3"] == "dev-a" and before["c2"] == "dev-b"
        assert _rows(s, "SELECT state FROM trade_orders WHERE id = ?",
                    (oid,))[0]["state"] == "pending"
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 1}, counts   # только от oid2

    def test_accept_want_deficit_is_card_gone_taker(self, tmp_path, monkeypatch):
        """Симметричный отказ: дефицит на второй WANT-позиции — card_gone:taker.

        taker сам дарит stone maker'у между оффером и accept — его коллекция
        изменилась, а want валидился по ней на момент оффера. Отказ так же
        атомен: обе give-позиции остаются у maker'а.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c3", "coal", "Уголь", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00"),
                           ("c9", "stone", "Камень", "2026-01-04T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "spark"}, {"card_id": "coal"}],
                     want=[{"card_id": "ice"}, {"card_id": "stone"}]).json()["id"]
        assert _gift(client, "dev-b", "dev-a",
                     give=[{"card_id": "stone"}]).status_code == 200
        before = _owners(s)
        assert before["c9"] == "dev-a", "подарок унёс stone у taker'а"
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone:taker")
        assert _owners(s) == before, "первая want-позиция не поехала встречно"
        assert _rows(s, "SELECT state FROM trade_orders WHERE id = ?",
                    (oid,))[0]["state"] == "pending"
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-b": 1}, counts               # только за подарок

    def test_accept_nm_moves_all_positions_to_right_owners(self, tmp_path, monkeypatch):
        """Счастливый путь 2×1: уехали ВСЕ позиции, правами сторонами, без
        частичных переносов; moved_in/moved_out (S2-совместимые поля) — первые
        (min pos) позиции каждой стороны, полный состав — из list (Task 4)."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c3", "coal", "Уголь", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "spark"}, {"card_id": "coal"}],
                     want=[{"card_id": "ice"}]).json()["id"]
        r = _accept(client, "dev-b", oid)
        assert r.status_code == 200, r.text
        assert _owners(s) == {"c1": "dev-b", "c3": "dev-b", "c2": "dev-a"}
        body = r.json()
        assert body["moved_in"] == {"craft_id": "c1", "card_id": "spark",
                                    "llm_name": "Искра"}, body
        assert body["moved_out"] == {"craft_id": "c2", "card_id": "ice",
                                     "llm_name": "Лёд"}, body
        assert body["remain"] == 9 and body["peer_remain"] == 9
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "accepted"
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 1}, counts   # одно действие, не три

    def test_accept_two_copies_of_view_move_distinct_instances(self, tmp_path,
                                                               monkeypatch):
        """Две give-позиции одного вида уезжают ДВУМЯ разными экземплярами
        (старший первым), а не дважды одним craft_id — тот же инвариант,
        что у gift (`test_gift_two_copies_move_distinct_instances`)."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c8", "spark", "Искра вторая", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c2", "ice", "Лёд", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "spark"}, {"card_id": "spark"}],
                     want=[{"card_id": "ice"}]).json()["id"]
        r = _accept(client, "dev-b", oid)
        assert r.status_code == 200, r.text
        assert _owners(s) == {"c1": "dev-b", "c8": "dev-b", "c2": "dev-a"}
        col = client.get("/api/sigil/collection",
                         params={"device_id": "dev-b"}).json()
        assert col["cards"]["spark"]["copies"] == 2


def _cancel(client, device_id, order_id):
    return client.post("/api/trade/cancel",
                       json={"device_id": device_id, "id": order_id})


def _gift(client, device_id, to, give=None):
    """Списочная форма NM §2.2 (gift = give-список, want нет). Дефолт — прежний
    S2-литерал card='spark'."""
    return client.post("/api/trade/gift", json={
        "device_id": device_id, "to": to,
        "give": [{"card_id": "spark"}] if give is None else give})


class TestCancelGift:
    def test_offer_and_cancel_do_not_spend_limit(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _fill_week(s, ("dev-a",), count=9)
        for _ in range(3):
            oid = _offer(client, "dev-a", "dev-b", give=[{"card_id": "spark"}]).json()["id"]
            assert _cancel(client, "dev-a", oid).status_code == 200
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 9}, counts                                     # кейс 4a

    def test_cancel_withdraws_pending_row_only(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _cancel(client, "dev-a", oid)
        assert r.status_code == 200, r.text
        assert r.json() == {"ok": True, "id": oid}
        row = _rows(s, "SELECT * FROM trade_orders")[0]
        assert row["state"] == "cancelled"
        assert row["updated_at"] >= row["created_at"]
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b"}      # карты не тронуты
        assert _rows(s, "SELECT * FROM trade_counts") == []      # и лимит не тронут
        # снятый оффер нельзя принять — тот же 404, что у несуществующего
        r = _accept(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (404, "not_found")

    def test_cancel_error_matrix(self, tmp_path, monkeypatch):
        """Каждый код cancel проверяется отдельно: not_maker ≠ not_pending."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        r = _cancel(client, "dev-b", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "not_maker")
        r = _cancel(client, "dev-z", oid)
        assert (r.status_code, r.json()["detail"]) == (404, "not_registered")
        assert _cancel(client, "npc-spirit", oid).status_code == 400              # кейс 6
        r = _cancel(client, "dev-a", 987654)
        assert (r.status_code, r.json()["detail"]) == (404, "not_found")
        # раллинг 3c: гейт `_TRADE_ID_MAX` переиспользуется здесь, а не «своя
        # граница на каждую ручку». Без него bind'инг 10**30 падает в
        # OverflowError = 500 без машинного кода (§7).
        r = _cancel(client, "dev-a", 10 ** 30)
        assert (r.status_code, r.json()["detail"]) == (404, "not_found")
        assert _cancel(client, "dev-a", oid).status_code == 200
        r = _cancel(client, "dev-a", oid)
        assert (r.status_code, r.json()["detail"]) == (409, "not_pending")
        assert _rows(s, "SELECT * FROM trade_orders")[0]["state"] == "cancelled"

    def test_gift_moves_card_and_charges_giver_only(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _gift(client, "dev-a", "dev-b", give=[{"card_id": "spark"}])
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["craft_id"] == "c1" and body["moved_name"] == "Искра"
        assert body["remain"] == 9                                                # кейс 10
        assert _owners(s) == {"c1": "dev-b"}
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1}, counts          # у получателя лимит не тронут
        col = client.get("/api/sigil/collection",
                         params={"device_id": "dev-b"}).json()
        assert col["cards"]["spark"]["copies"] == 1    # и копия у него ровно одна
        row = _rows(s, "SELECT * FROM trade_orders")[0]
        assert row["state"] == "accepted"
        # §6, §6.1 + NM §2.1: у подарка только give-позиции, want пуст
        assert _items_of(s, row["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0}]

    def test_gift_chromatic_moves_exactly_that_instance(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("x1", "", "Радуга", "2026-01-01T00:00:00"),
                           ("p1", "spark", "Искра", "2026-01-02T00:00:00")])
        body = _gift(client, "dev-a", "dev-b", give=[{"craft_id": "x1"}]).json()
        assert (body["craft_id"], body["moved_name"]) == ("x1", "Радуга")
        assert _owners(s) == {"x1": "dev-b", "p1": "dev-a"}
        # чужой экземпляр — не подарок: _trade_pick_row ищет его у ME;
        # ruling 1: S2 card_not_owned 422 → not_enough_copies 409
        r = _gift(client, "dev-a", "dev-b", give=[{"craft_id": "x2"}])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert {x["device_id"]: x["count"] for x in
                _rows(s, "SELECT * FROM trade_counts")} == {"dev-a": 1}, \
            "чужой craft_id не списывает лимит повторно"

    def test_gift_guards(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _player(client, "Варя", "dev-v")
        r = _gift(client, "dev-a", "dev-v", give=[{"card_id": "spark"}])
        assert (r.status_code, r.json()["detail"]) == (404, "not_friends")        # кейс 20
        assert _owners(s) == {"c1": "dev-a"}, "карта обязана остаться на месте"
        assert _rows(s, "SELECT * FROM trade_orders") == []
        assert _rows(s, "SELECT * FROM trade_counts") == [], \
            "отказ не тратит недельный лимит дарителя"
        # пустая позиция — bad_item (ruling 1: прежний bad_selector), пустой
        # список — side_too_long: gift = offer без want, гейты сторон общие
        r = _gift(client, "dev-a", "dev-b", give=[{}])
        assert (r.status_code, r.json()["detail"]) == (422, "bad_item")           # кейс 8
        r = _gift(client, "dev-a", "dev-b", give=[])
        assert (r.status_code, r.json()["detail"]) == (422, "side_too_long")
        r = _gift(client, "dev-a", "dev-a", give=[{"card_id": "spark"}])
        assert (r.status_code, r.json()["detail"]) == (422, "self_deal")          # кейс 9
        r = _gift(client, "dev-a", "dev-b", give=[{"card_id": "mist"}])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")  # кейс 15
        assert _rows(s, "SELECT * FROM trade_orders") == []
        assert _rows(s, "SELECT * FROM trade_counts") == [], \
            "нет карты — нет и списания лимита"
        assert _gift(client, "npc-spirit", "dev-a",
                     give=[{"card_id": "spark"}]).status_code == 400

    def test_gift_rejects_when_receiver_holds_that_craft_id(self, tmp_path, monkeypatch):
        """Раллинг 3d: одинаковый `craft_id` у двух игроков — не выдумка теста.

        `craft_id = f"{day}_{device_id[:8]}_{index}"` — форма строится в двух
        местах, координаты даёт `grep -n 'device_id\\[:8\\]' server.py`
        берёт первые 8 символов клиентского id, поэтому две легальные строки
        (PK — пара `(device_id, craft_id)`) могут назваться одинаково, и `UPDATE`
        переездом на такой PK дал бы `IntegrityError` = 500 вместо машинного
        кода. Состояние собрано `_seed`'ом напрямую, потому что выловить
        коллизию через `/api/sigil/craft` в тесте — это два игрока с общим
        префиксом; достижимость через публичные ручки доказана ревьюером
        (`task-4-review.md` F1, `repro/review_repro.py`).
        `_owners()` здесь не годится: он схлопывает карту `{craft_id: device}`
        в один ключ ровно на коллизии, поэтому проверка — явный список строк.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("K", "spark", "Искра", "2026-01-01T00:00:00")])
        _seed(s, "dev-b", [("K", "ice", "Лёд", "2026-01-02T00:00:00")])
        r = _gift(client, "dev-a", "dev-b", give=[{"card_id": "spark"}])
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone")
        assert _rows(s, "SELECT device_id, craft_id FROM sigil_crafts"
                        " ORDER BY device_id") == [
            {"craft_id": "K", "device_id": "dev-a"},
            {"craft_id": "K", "device_id": "dev-b"}], "отказ обязан быть до записи"
        assert _rows(s, "SELECT * FROM trade_orders") == []
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_gift_week_limit_stops_before_any_write(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _fill_week(s, ("dev-a",))
        r = _gift(client, "dev-a", "dev-b", give=[{"card_id": "spark"}])
        assert (r.status_code, r.json()["detail"]) == (409, "week_limit")
        assert _owners(s) == {"c1": "dev-a"}
        assert _rows(s, "SELECT * FROM trade_orders") == [], "строки не должно быть"
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 10}, counts

    def test_gift_limit_ignores_receiver_week_count(self, tmp_path, monkeypatch):
        """Недельный лимит в gift тратит только даритель (спека §6, шаг 3).

        Пинит одиночество `me` в `server.py:5988`
        (`if _trade_week_count(conn, week, me) >= TRADE_WEEK_LIMIT`). Мутация
        «считать и получателя», как это делает accept, обязана краснить ровно этот
        тест: dev-b стоит на лимите, а подарок обязан пройти и вырастить только
        счётчик dev-a. Зеркальный случай (даритель на лимите = отказ без записей)
        прижат соседним тестом выше, поэтому здесь нужна именно асимметрия.
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        _fill_week(s, ("dev-b",))
        r = _gift(client, "dev-a", "dev-b", give=[{"card_id": "spark"}])
        assert r.status_code == 200, r.text
        body = r.json()
        assert (body["ok"], body["craft_id"], body["remain"]) == (True, "c1", 9)
        assert _owners(s) == {"c1": "dev-b"}
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1, "dev-b": 10}, counts


class TestGiftNM:
    """Ruling 15 (ledger): gift остаётся мгновенной передачей, но payload —
    give-список, и ВСЕ позиции уезжают атомарно: дефицит или коллизия любой
    позиции → 409, ноль переносов, ни строки в trade_orders/trade_items."""

    def test_gift_moves_all_positions_atomically(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("x1", "", "Радуга", "2026-01-02T00:00:00"),
                           ("c7", "ice", "Лёд", "2026-01-03T00:00:00")])
        r = _gift(client, "dev-a", "dev-b", give=[
            {"card_id": "spark"}, {"craft_id": "x1"}, {"card_id": "ice"}])
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["craft_id"] == "c1" and body["remain"] == 9
        assert _owners(s) == {"c1": "dev-b", "x1": "dev-b", "c7": "dev-b"}
        orders = _rows(s, "SELECT * FROM trade_orders")
        assert len(orders) == 1 and orders[0]["state"] == "accepted"
        assert _items_of(s, orders[0]["id"]) == [
            {"side": "give", "card_id": "spark", "craft_id": "", "pos": 0},
            {"side": "give", "card_id": "", "craft_id": "x1", "pos": 1},
            {"side": "give", "card_id": "ice", "craft_id": "", "pos": 2}]
        counts = {x["device_id"]: x["count"] for x in _rows(s, "SELECT * FROM trade_counts")}
        assert counts == {"dev-a": 1}, counts     # одно действие, не три (§2.3 п.6)

    def test_gift_deficit_on_any_position_moves_nothing(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00")])
        r = _gift(client, "dev-a", "dev-b",
                  give=[{"card_id": "spark"}, {"card_id": "mist"}])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert _owners(s) == {"c1": "dev-a"}, "первая позиция не уехала"
        assert _rows(s, "SELECT * FROM trade_orders") == []
        assert _rows(s, "SELECT * FROM trade_items") == []
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_gift_collision_on_any_position_moves_nothing(self, tmp_path, monkeypatch):
        """Раллинг 3d в мульти-мире: занятый целевой PK у ВТОРОЙ позиции —
        отказ до первого UPDATE, и первая (свободная) позиция тоже не едет."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("K", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c7", "ice", "Лёд", "2026-01-02T00:00:00")])
        _seed(s, "dev-b", [("c7", "stone", "Камень", "2026-01-03T00:00:00")])
        r = _gift(client, "dev-a", "dev-b",
                  give=[{"card_id": "spark"}, {"card_id": "ice"}])
        assert (r.status_code, r.json()["detail"]) == (409, "card_gone"), r.text
        assert {(x["device_id"], x["craft_id"]) for x in _rows(
            s, "SELECT device_id, craft_id FROM sigil_crafts")} == {
            ("dev-a", "K"), ("dev-a", "c7"), ("dev-b", "c7")}, "отказ до записи"
        assert _rows(s, "SELECT * FROM trade_orders") == []
        assert _rows(s, "SELECT * FROM trade_items") == []
        assert _rows(s, "SELECT * FROM trade_counts") == []

    def test_gift_two_copies_move_distinct_instances(self, tmp_path, monkeypatch):
        """Две ячейки одного вида забирают ДВА разных экземпляра (старший —
        первый), а не дважды один и тот же craft_id."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c8", "spark", "Искра вторая", "2026-01-02T00:00:00")])
        r = _gift(client, "dev-a", "dev-b",
                  give=[{"card_id": "spark"}, {"card_id": "spark"}])
        assert r.status_code == 200, r.text
        assert _owners(s) == {"c1": "dev-b", "c8": "dev-b"}
        col = client.get("/api/sigil/collection",
                         params={"device_id": "dev-b"}).json()
        assert col["cards"]["spark"]["copies"] == 2

    def test_gift_chromatic_twice_is_deficit(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("x1", "", "Радуга", "2026-01-01T00:00:00"),
                           ("c1", "spark", "Искра", "2026-01-02T00:00:00")])
        r = _gift(client, "dev-a", "dev-b",
                  give=[{"craft_id": "x1"}, {"craft_id": "x1"}])
        assert (r.status_code, r.json()["detail"]) == (409, "not_enough_copies")
        assert _owners(s) == {"x1": "dev-a", "c1": "dev-a"}
        assert _rows(s, "SELECT * FROM trade_orders") == []


class TestListAndBadge:
    def test_list_splits_incoming_outgoing_and_history(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _seed(s, "dev-b", [("x1", "", "Радуга", "2026-01-03T00:00:00")])
        out_oid = _offer(client, "dev-a", "dev-b",
                         give=[{"card_id": "spark"}], want=[{"craft_id": "x1"}]).json()["id"]
        in_oid = _offer(client, "dev-b", "dev-a",
                        give=[{"card_id": "ice"}], want=[{"card_id": "spark"}]).json()["id"]
        body = client.get("/api/trade/list", params={"device_id": "dev-a"}).json()
        assert [o["id"] for o in body["outgoing"]] == [out_oid]
        assert [o["id"] for o in body["incoming"]] == [in_oid]
        assert body["history"] == []
        assert body["week_limit"] == 10 and body["remain"] == 10      # кейс 13
        row = body["outgoing"][0]
        assert row["maker_device"] == "dev-a" and row["taker_device"] == "dev-b"
        assert row["maker_nick"] == "Аня" and row["taker_nick"] == "Николя"
        assert row["state"] == "pending"
        # NM §2.2 (редакция S2-правила): сервер называет ВСЕ позиции — карту
        # вида по fallback_name каталога фикстуры, хроматик по llm_name
        # текущего носителя. Классификация строки и имена — прежние пины.
        assert row["give_items"] == [{"card_id": "spark", "craft_id": "", "name": "Spark"}]
        assert row["want_items"] == [{"card_id": "", "craft_id": "x1", "name": "Радуга"}]
        assert _accept(client, "dev-b", out_oid).status_code == 200
        body = client.get("/api/trade/list", params={"device_id": "dev-a"}).json()
        assert [h["id"] for h in body["history"]] == [out_oid]
        assert [o["id"] for o in body["outgoing"]] == []
        assert body["remain"] == 9                                    # кейс 13
        # после accepted экземпляр носит уже не maker: имя взято у текущего
        assert body["history"][0]["want_items"][0]["name"] == "Радуга"
        assert body["history"][0]["give_items"][0]["name"] == "Spark"

    def test_incoming_chromatic_is_named_by_makers_instance(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-b", [("x1", "", "Радуга", "2026-01-01T00:00:00")])
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-02T00:00:00")])
        _offer(client, "dev-b", "dev-a", give=[{"craft_id": "x1"}], want=[{"card_id": "spark"}])
        row = client.get("/api/trade/list",
                         params={"device_id": "dev-a"}).json()["incoming"][0]
        assert row["give_items"] == [{"card_id": "", "craft_id": "x1", "name": "Радуга"}]
        assert row["want_items"] == [{"card_id": "spark", "craft_id": "", "name": "Spark"}]

    def test_accepted_chromatic_give_is_named_by_taker(self, tmp_path, monkeypatch):
        """Имя give-хроматика после accept берётся у НОВОГО носителя.

        Ветка `state == 'accepted' → taker_device` в `_trade_give_owner` иначе
        мертва: имена карт вида в `test_list_splits_incoming_outgoing_and_history`
        рисует каталог и они от носителя не зависят вообще, поэтому замена
        `_trade_give_owner` на «всегда maker» не изменила бы ни одной подписи
        вида (проверено мутацией). Здесь `x1` после accept лежит у taker'а, так
        что maker-ключ дал бы "" — список выдал бы безымянный экземпляр (§2.2:
        имя хроматика у текущего носителя).
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-b", [("x1", "", "Радуга", "2026-01-01T00:00:00"),
                           ("c9", "ice", "Лёд", "2026-01-02T00:00:00")])
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-b", "dev-a",
                     give=[{"craft_id": "x1"}], want=[{"card_id": "spark"}]).json()["id"]
        row = client.get("/api/trade/list",
                         params={"device_id": "dev-a"}).json()["incoming"][0]
        assert row["state"] == "pending"
        assert row["give_items"] == [{"card_id": "", "craft_id": "x1", "name": "Радуга"}]
        assert _accept(client, "dev-a", oid).status_code == 200
        assert _owners(s) == {"c1": "dev-b", "x1": "dev-a", "c9": "dev-b"}
        hist = client.get("/api/trade/list",
                          params={"device_id": "dev-b"}).json()["history"][0]
        assert hist["id"] == oid and hist["give_items"][0]["craft_id"] == "x1"
        assert hist["give_items"][0]["name"] == "Радуга", "имя у текущего носителя, не у maker'а"
        # карту вида сервер называет каталогом (NM §2.2), экземпляр для неё
        # выбрал accept и в строке оффера он не записан — имя берётся из вида.
        assert hist["want_items"][0]["card_id"] == "spark" and \
            hist["want_items"][0]["name"] == "Spark"

    def test_expired_pending_is_hidden_but_row_survives(self, tmp_path, monkeypatch):
        """Ленивая TTL (§6.1): list не отдаёт, accept отказывает, строка живёт."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        stale = _stale_iso(s)
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("UPDATE trade_orders SET created_at = ? WHERE id = ?",
                     (stale, oid))
        conn.commit()
        conn.close()
        # премиса, а не удача по календарю (тот же идиом, что в
        # test_expired_offer_is_409): дата-литерал проверял бы TTL-настройку
        # прогона, а не правило.
        assert stale < s._trade_ttl_cutoff(), (stale, s._trade_ttl_cutoff())
        for dev in ("dev-a", "dev-b"):
            body = client.get("/api/trade/list", params={"device_id": dev}).json()
            assert body["incoming"] == [] and body["outgoing"] == []
            assert body["history"] == []
        assert _rows(s, "SELECT state FROM trade_orders")[0]["state"] == "pending"

    def test_list_rejects_reserved_caller_ids(self, tmp_path, monkeypatch):
        """§7 строка `list`: 400 от `_social_caller`, и раньше SELECT'а профиля.

        Список — чтение чужого графа обмена, ровно как лента со Светиком, и
        кейс 6 требует тот же гейт здесь. `npc-spirit` и `bot-1` в этом прогоне
        НЕ заведены, поэтому 400 вместо 404 `not_registered` — это заодно и
        доказательство порядка: гейт вызывающего стоит до `_trade_registered`.
        Мутант — убрать `me = _social_caller(device_id)`: оба зарезервированных
        id станут 404, а `"   "` — 500 (пустой id дойдёт до SQL).
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        for bad, code in (("npc-spirit", "npc"), ("bot-1", "bot"),
                          ("   ", "bad_device_id"), ("dev-a|dev-b", "bad_device_id")):
            r = client.get("/api/trade/list", params={"device_id": bad})
            assert (r.status_code, r.json()["detail"]) == (400, code), (bad, r.text)

    def test_list_without_profile_is_not_registered(self, tmp_path, monkeypatch):
        """§7 строка `list`: 404 `not_registered`, а не 200 с тремя пустыми списками.

        Мутант — убрать `_trade_registered(conn, me)`: хендлер вернёт 200 и
        пустые среди, а соседний тест этого не заметит, потому что его dev-a и
        dev-b как раз зарегистрированы. Тихий пустой ответ для аккаунта без
        профиля — сломанный клиент (Task 10 по такому ответу рисует пустую
        вкладку вместо «заведите профиль»).
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        r = client.get("/api/trade/list", params={"device_id": "dev-ghost"})
        assert (r.status_code, r.json()["detail"]) == (404, "not_registered"), r.text

    def test_inbox_badge_counts_incoming_pending_only(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)

        def badge(dev):
            r = client.get("/api/social/inbox", params={"device_id": dev})
            assert r.status_code == 200, r.text
            return r.json()["trades_pending"]

        assert badge("dev-a") == 0 and badge("dev-b") == 0
        oid = _offer(client, "dev-a", "dev-b").json()["id"]
        assert badge("dev-b") == 1                                    # кейс 19
        assert badge("dev-a") == 0          # свои исходящие в бейдж не входят (§8.5)
        _accept(client, "dev-b", oid)
        assert badge("dev-a") == 0 and badge("dev-b") == 0
        # просроченный входящий не бейджит: тот же cutoff, что у list. Второй
        # оффер — coal, а не spark: spark уехал принатым оффером выше, а `_both(s)`
        # даёт dev-a ровно одну карту, поэтому здесь нужна вторая строка коллекции.
        # want=[] (NM §2.2): после обмена ice лежит у maker'а, и дефолтный
        # want=[ice] краснел бы в peer_lacks на offer; бейдж и TTL от этого
        # не меняются — asserted-строки прежние.
        _seed(s, "dev-a", [("c5", "coal", "Уголь", "2026-01-03T00:00:00")])
        oid2 = _offer(client, "dev-a", "dev-b", give=[{"card_id": "coal"}],
                      want=[]).json()["id"]
        stale = _stale_iso(s)
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("UPDATE trade_orders SET created_at = ? WHERE id = ?",
                     (stale, oid2))
        conn.commit()
        conn.close()
        assert stale < s._trade_ttl_cutoff(), (stale, s._trade_ttl_cutoff())
        assert badge("dev-b") == 0

    def test_milestones_are_not_minted_by_trades(self, tmp_path, monkeypatch):
        """Кейс 14: порог сверяется с КОЛЛЕКЦИЕЙ В МОМЕНТ КЛЕЙМА, обмен не минтит вехи.

        Три шага — три разных мутанта:
        1. ember/coal уходит принатым оффером → клейм tier 3 отказывает. Краснеет
           на «историческом» множестве card_id (сервер считал бы когда-либо
           приобретённые, а не текущие) — единственном способе пройти порог после
           потери карты.
        2. карта возвращается подарком → клейм проходит и пишет РОВНО одну строку.
           Второй клейм идемпотентен (claimed=false, строка одна).
        3. карта уходит снова → `sigil_milestones` всё ещё [3]. Краснеет на любом
           отзыве вехи и на начислении вехи самим обменом (пустые проверки между
           шагами ловят «трейд дописал строку»).
        """
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-a", [("c1", "spark", "Искра", "2026-01-01T00:00:00"),
                           ("c2", "coal", "Уголь", "2026-01-02T00:00:00"),
                           ("c3", "ember", "Уголек", "2026-01-03T00:00:00")])
        _seed(s, "dev-b", [("c9", "ice", "Лёд", "2026-01-04T00:00:00")])

        def claim(dev, tier):
            r = client.post("/api/sigil/milestone",
                            json={"device_id": dev, "set": "fire", "tier": tier})
            assert r.status_code == 200, r.text
            return r.json()

        def mine(dev):
            return [r["tier"] for r in _rows(
                s, "SELECT tier FROM sigil_milestones WHERE device_id = ?", (dev,))]

        # шаг 1: у dev-a остаётся 2 карты из 3 (в фикстуре у сета fire ровно 3
        # card_ids, поэтому tier 3 = «весь сет»). Порог меряется по текущему.
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "coal"}], want=[{"card_id": "ice"}]).json()["id"]
        assert _accept(client, "dev-b", oid).status_code == 200
        assert _owners(s) == {"c1": "dev-a", "c2": "dev-b", "c3": "dev-a", "c9": "dev-a"}
        dead = claim("dev-a", 3)
        assert (dead["ok"], dead["error"]) == (False, "not_enough_cards")        # §5.3
        assert mine("dev-a") == [] and mine("dev-b") == []
        # шаг 2: комплект вернулся (подарок, а не оффер: у dev-b больше нет ice)
        assert _gift(client, "dev-b", "dev-a", give=[{"card_id": "coal"}]).status_code == 200
        got = claim("dev-a", 3)
        assert (got["ok"], got["claimed"], got["set"]) == (True, True, "fire")
        again = claim("dev-a", 3)
        assert (again["ok"], again["claimed"]) == (True, False)
        assert mine("dev-a") == [3], "повторный клейм не пишет вторую строку"
        # шаг 3: карта снова ушла — забранное не отнимается, а обмен не дописал
        assert _gift(client, "dev-a", "dev-b", give=[{"card_id": "coal"}]).status_code == 200
        assert claim("dev-a", 3)["ok"] is False
        assert mine("dev-a") == [3], "забранное не отнимается"


class TestListNM:
    """NM §2.2: строки трёх среди несут give_items/want_items с серверными
    именами; одиночные S2-ключи исчезли из ответа."""

    def test_list_rows_carry_items_and_names(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _seed(s, "dev-b", [("x1", "", "Радуга", "2026-01-05T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "spark"}], want=[{"craft_id": "x1"}]).json()["id"]
        body = client.get("/api/trade/list", params={"device_id": "dev-b"}).json()
        row = [r for r in body["incoming"] if r["id"] == oid][0]
        # Имя карты вида — fallback_name каталога фикстуры (не выдуманное:
        # TRADE_CATALOG задаёт "Spark"/"Ice"…); хроматика — llm_name экземпляра.
        assert row["give_items"] == [{"card_id": "spark", "craft_id": "", "name": "Spark"}]
        assert row["want_items"] == [{"card_id": "", "craft_id": "x1", "name": "Радуга"}]
        assert "give_card_id" not in row and "want_name" not in row

    def test_list_rows_items_ordered_by_pos_and_want_empty(self, tmp_path, monkeypatch):
        """Позиции идут в порядке хранения pos, want-пустой оффер — пустой массив."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _both(s)
        _seed(s, "dev-a", [("c5", "coal", "Уголь", "2026-01-03T00:00:00")])
        oid = _offer(client, "dev-a", "dev-b",
                     give=[{"card_id": "coal"}, {"card_id": "spark"}], want=[]).json()["id"]
        row = [r for r in client.get("/api/trade/list",
                                     params={"device_id": "dev-b"}).json()["incoming"]
               if r["id"] == oid][0]
        assert row["give_items"] == [
            {"card_id": "coal", "craft_id": "", "name": "Coal"},
            {"card_id": "spark", "craft_id": "", "name": "Spark"}]
        assert row["want_items"] == []

    def test_list_rows_unknown_view_named_by_raw_id(self, tmp_path, monkeypatch):
        """Каталог не знает вид — имя = сырой card_id (§2.2: история обязана
        читаться и после смены комплекта). Строка вставлена в обход ручки, как
        `_order`: отменить оффер неизвестной картой через API нельзя."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        conn = sqlite3.connect(s.DB_PATH)
        cur = conn.execute(
            "INSERT INTO trade_orders (maker_device, taker_device, state,"
            " created_at, updated_at) VALUES (?,?,?,?,?)",
            ("dev-a", "dev-b", "cancelled", "2026-01-06T00:00:00", "2026-01-06T00:00:00"))
        conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                     " VALUES (?, 'give', 'mercury', '', 0)", (cur.lastrowid,))
        conn.execute("INSERT INTO trade_items (order_id, side, card_id, craft_id, pos)"
                     " VALUES (?, 'want', 'topaz', '', 0)", (cur.lastrowid,))
        conn.commit()
        conn.close()
        body = client.get("/api/trade/list", params={"device_id": "dev-a"}).json()
        assert [h["id"] for h in body["history"]] == [cur.lastrowid]
        row = body["history"][0]
        assert row["give_items"] == [{"card_id": "mercury", "craft_id": "", "name": "mercury"}]
        assert row["want_items"] == [{"card_id": "topaz", "craft_id": "", "name": "topaz"}]


class TestPeerCollectionNM:
    """NM §2.2: GET /api/trade/peer_collection — состав своей коллекции без
    майлстоунов, гейт — только принятая дружба (403 not_friends)."""

    def test_peer_collection_matches_own_shape(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _seed(s, "dev-b", [("c9", "ice", "Лёд", "2026-01-01T00:00:00"),
                           ("x1", "", "Радуга", "2026-01-02T00:00:00")])
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute("INSERT INTO sigil_milestones (device_id, set_id, tier, claimed_at)"
                     " VALUES ('dev-b', 'fire', 1, '2026-01-03T00:00:00')")
        conn.commit()
        conn.close()
        own = client.get("/api/sigil/collection", params={"device_id": "dev-b"}).json()
        assert own["milestones"] == {"fire": [1]}                     # премиса: веха есть
        peer = client.get("/api/trade/peer_collection",
                          params={"device_id": "dev-a", "peer": "dev-b"}).json()
        assert peer["ok"] is True
        assert peer["cards"] == own["cards"] and peer["extras"] == own["extras"]
        assert "milestones" not in peer                               # §2.2: другу не нужен

    def test_peer_collection_requires_accepted_friendship(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        _player(client, "Пётр", "dev-c")
        # Незнакомец, сам себе и непринятый запрос — все 403 not_friends.
        for peer in ("dev-c", "dev-a"):
            r = client.get("/api/trade/peer_collection",
                           params={"device_id": "dev-a", "peer": peer})
            assert (r.status_code, r.json()["detail"]) == (403, "not_friends"), (peer, r.text)
        assert client.post("/api/friend/request", json={"device_id": "dev-a",
                                                        "target_nick": "Пётр"}).status_code == 200
        r = client.get("/api/trade/peer_collection",
                       params={"device_id": "dev-a", "peer": "dev-c"})
        assert (r.status_code, r.json()["detail"]) == (403, "not_friends"), r.text
        # …а после принятия — 200 (гейт читает именно state ребра).
        assert client.post("/api/friend/respond", json={"device_id": "dev-c",
                                                        "requester_device": "dev-a",
                                                        "accept": True}).status_code == 200
        r = client.get("/api/trade/peer_collection",
                       params={"device_id": "dev-a", "peer": "dev-c"})
        assert r.status_code == 200 and r.json()["ok"] is True

    def test_peer_collection_caller_gates_before_payload(self, tmp_path, monkeypatch):
        """Порядок гейтов: формальный id звонящего (400) → его профиль (404) →
        дружба (403). Зарезервированные id в этом прогоне не заведены, поэтому
        400 вместо 404 доказывает, что `_social_caller` стоит до `_trade_registered`."""
        s = _srv(tmp_path, monkeypatch)
        client = _trade_client(s, tmp_path, monkeypatch)
        _friends(client)
        for bad, code in (("npc-spirit", "npc"), ("bot-1", "bot"),
                          ("   ", "bad_device_id"), ("dev-a|dev-b", "bad_device_id")):
            r = client.get("/api/trade/peer_collection",
                           params={"device_id": bad, "peer": "dev-b"})
            assert (r.status_code, r.json()["detail"]) == (400, code), (bad, r.text)
        r = client.get("/api/trade/peer_collection",
                       params={"device_id": "dev-ghost", "peer": "dev-b"})
        assert (r.status_code, r.json()["detail"]) == (404, "not_registered"), r.text
