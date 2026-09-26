"""U5 (T04 + T08) + T29 (I-1): неблокирующий event loop + атомарность гонок.

Регрессии на РЕАЛЬНЫХ потоках против настоящих хендлеров server.py (после T04
это sync `def`, поэтому вызываются напрямую — та же кодовая путь, что и под
uvicorn, без копий логики в тесте).

Инварианты:
- любой HTTP-хендлер, в чьём теле есть get_db(), — синхронная `def`: его ведёт
  threadpool, и ни генерация, ни ожидание WAL-лока (DB_BUSY_TIMEOUT_SEC) не
  морозят event loop и /api/health. После T29 это ПРАВИЛО, а не список из четырёх
  «генерирующих» имён; «читающие остаются async» из старой формулировки было
  правдой лишь для 4 из 27 хендлеров (brew_check, например, регистрирует
  устройство и коммитит — он не читающий);
- две параллельные варки ОДНОЙ новой пары: генерация ровно одна, проигравший
  получает 409 («в обработке») или known — никогда второй created;
- лок-строка pending_pairs не оставляется ни после успеха, ни после отказа
  валидации (400), ни после rate_limited — «могилы» state='resolved' больше
  не плодятся (T08.2);
- _ensure_challenge: параллельное создание «дня» без IntegrityError-500 (T08.3);
- писма: параллельные letter/today одного устройства — одна строка без 500.

Прямое доказательство атомарности SQL-переходов под потоками без fastapi —
tests/harness_atomicity_u5.py (прогоняется и как скрипт, и как test_atomicity_harness).
"""
import ast
import asyncio
import inspect
import os
import sqlite3
import sys
import textwrap
import threading
import time

import pytest

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

server = pytest.importorskip("server")  # нужен fastapi; в окружении T09 есть


class _StubLLM:
    """Заглушка генератора: provider=mock — квоты (внешний бюджет) не тратятся,
    generate/generate_hint тормозят, как настоящая LLM, чтобы поймать гонку."""

    provider = "mock"
    models = []
    api_key = ""

    def __init__(self, delay: float = 0.5, name: str = "Тествещество"):
        self.delay = delay
        self.name = name
        self._lock = threading.Lock()
        self.generate_calls = []
        self.hint_calls = []

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        with self._lock:
            self.generate_calls.append(pair_key)
        time.sleep(self.delay)
        return {"combinable": True, "name": self.name,
                "glyph": "", "description": "", "tag": ""}

    def generate_hint(self, a_name, b_name):
        with self._lock:
            self.hint_calls.append((a_name, b_name))
        time.sleep(self.delay)
        return {"hint": "проба и проба"}


@pytest.fixture()
def app_db(tmp_path, monkeypatch):
    """Чистая БД на tmp + подменённый LLM-синглтон. init_db() — тот же, что в проде."""
    db = str(tmp_path / "u5.db")
    monkeypatch.setattr(server, "DB_PATH", db)
    stub = _StubLLM()
    monkeypatch.setattr(server, "_LLM_GEN", stub)
    server.init_db()
    return db, stub


def _req(a, b, device="dev-u5", nick=None):
    return server.DiscoverRequest(a=a, b=b, nick=nick or f"ник-{device}", device_id=device)


def _pair_keys(conn):
    return conn.execute(
        "SELECT COUNT(*) FROM recipes WHERE pair_key = ?", (PK,)
    ).fetchone()[0]


def _pending_count(conn):
    return conn.execute("SELECT COUNT(*) FROM pending_pairs").fetchone()[0]


PK = "fire|gold"  # обе слаги есть в стартовом графе, рецепта нет — свежая пара
# Пол «живости» интроспекции в test_generating_handlers_are_sync_def: в HEAD это
# 26 HTTP-хендлеров приложения плюс служебные роуты FastAPI (openapi/docs/redoc).
# Нужен, чтобы тест не позеленел «молча», когда фильтр перестанет что-либо видеть.
_HTTP_ROUTE_FLOOR = 25


# --- T04+T29: форма хендлеров (инвариант, а не список имён) ------------------

def _http_endpoints():
    """Эндпоинты HTTP-роутов приложения (роуты с methods).

    on_event-обработчики (startup) в app.routes не лежат, а служебные роуты
    FastAPI (openapi/docs) здесь останутся — они просто не зовут get_db() и под
    правило не попадают.
    """
    out = {}
    for route in server.app.routes:
        endpoint = getattr(route, "endpoint", None)
        if endpoint is None or not getattr(route, "methods", None):
            continue
        name = getattr(endpoint, "__name__", "")
        if name:
            out.setdefault(name, endpoint)
    return out


def _db_handlers():
    """Хендлеры, в чьём ТЕЛЕ встречается вызов get_db() — то есть идущие в SQLite.

    T29 (I-1): правило вместо перечисления. Именно тело, а не «генерирующий ли
    это эндпоинт»: brew_check регистрирует устройство и коммитит, поэтому он не
    «читющий», каким его закреплял старый пин.
    """
    found = {}
    for name, endpoint in _http_endpoints().items():
        try:
            tree = ast.parse(textwrap.dedent(inspect.getsource(endpoint)))
        except (OSError, TypeError):  # лямбда/синтетическая функция — не хендлер
            continue
        calls_db = any(
            isinstance(node, ast.Call)
            and getattr(node.func, "id", None) == "get_db"
            for node in ast.walk(tree)
        )
        if calls_db:
            found[name] = endpoint
    return found


def test_generating_handlers_are_sync_def():
    """Хендлер, трогающий SQLite, обязан быть sync `def` (ведёт threadpool).

    Различник (мутация, которая роняет этот тест): вернуть ЛЮБОЙ из найденных
    хендлеров в `async def` — например написать `async def brew_check(...)` или
    `async def echoes_claim(...)`. Тогда он попадёт в _db_handlers() как
    корутина, assert ниже краснеет, и «красным» он становится ровно из-за
    нарушения правила (такой хендлер зовёт sqlite3 с event loop'а и может
    держать loop запертым до DB_BUSY_TIMEOUT_SEC).

    Отдельные падения-от-пустоты (тест не должен «позеленеть», перестав что-либо
    видеть): если интроспекция app.routes сломается (смена внутреннего устройства
    FastAPI/Starlette) — red на _HTTP_ROUTE_FLOOR; если перестанет находиться
    вызов get_db() в теле — red на «brew_check ∈ db_handlers» (именно этот
    хендлер старый пин закреплял неверно).
    """
    endpoints = _http_endpoints()
    assert len(endpoints) >= _HTTP_ROUTE_FLOOR, (
        "интроспекция server.app.routes нашла только %d HTTP-эндпоинтов: "
        "фильтр по route.methods/endpoint сломался, тест стал бы пустым"
        % len(endpoints))
    db_handlers = _db_handlers()
    assert "brew_check" in db_handlers, (
        "правило get_db() не увидело brew_check (он точно пишет в БД): "
        "_db_handlers() больше не находит писателей — инвариант выродился")
    coroutine_writers = sorted(n for n, ep in db_handlers.items()
                               if inspect.iscoroutinefunction(ep))
    assert not coroutine_writers, (
        "хендлеры, ходящие в SQLite, обязаны быть sync `def` (threadpool), "
        "иначе они блокируют event loop на время блокировки WAL-писателя: "
        "%s" % coroutine_writers)
    # startup — осознанное ИСКЛЮЧЕНИЕ из правила: это не HTTP-хендлер, его зовут
    # через asyncio.run из tests/test_payments.py:313 и из
    # test_startup_purge_removes_legacy_tombstones ниже; корутиной он обязан
    # остаться, иначе оба теста валятся с TypeError.
    assert inspect.iscoroutinefunction(server.startup), (
        "startup больше не корутина — asyncio.run(srv.startup()) в тестах упадёт")
    assert "startup" not in db_handlers, (
        "startup попал в HTTP-роуты: фильтр _http_endpoints() перестал отделять "
        "on_event-обработчики, и исключение ниже потеряло смысл")
    # health — не «обязательно def»: он не ходит в get_db() и потому под правило
    # не подпадает. Пин сохранён (T04): дешёвый read-only контракт loop не морозит.
    assert inspect.iscoroutinefunction(server.health), (
        "health перестал быть async: он вне правила (в БД не ходит), но именно "
        "как дешёвый читющий контракт он и закреплён — см. T04")
    assert "health" not in db_handlers, (
        "health начал ходить в get_db(): он попадает под правило sync `def`, "
        "пин выше надо снимать вместе с конверсией")


# --- T08.1: атомарный захват пары -------------------------------------------

def test_concurrent_discover_same_new_pair_exactly_one_generates(app_db):
    db, stub = app_db
    barrier = threading.Barrier(2)
    outcomes = {}

    def brew(tag):
        barrier.wait(timeout=5)
        try:
            outcomes[tag] = ("resp", server.discover(_req("gold", "fire", device=f"dev-{tag}")))
        except Exception as e:  # noqa: BLE001
            outcomes[tag] = ("exc", e)

    ths = [threading.Thread(target=brew, args=(t,)) for t in ("a", "b")]
    [t.start() for t in ths]
    [t.join(timeout=10) for t in ths]

    assert len(outcomes) == 2
    kinds = {t: v[0] for t, v in outcomes.items()}
    # проигравший — HTTP 409 «пара в обработке»; победитель — created
    assert sorted(kinds.values()) == ["exc", "resp"], outcomes
    loser = [t for t, v in kinds.items() if v == "exc"][0]
    exc = outcomes[loser][1]
    assert isinstance(exc, server.HTTPException) and exc.status_code == 409
    winner = [t for t, v in kinds.items() if v == "resp"][0]
    resp = outcomes[winner][1]
    assert resp.ok and resp.status == "created"
    # ровно ОДИН LLM-вызов на гонку из двух потоков и ровно один рецепт
    assert stub.generate_calls == [PK], "генерация должна быть строго одна"
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    assert _pair_keys(conn) == 1
    assert _pending_count(conn) == 0, "после завершения гонки очередей лока не осталось"
    conn.close()


def test_pair_lock_helpers_grab_decline_regrab(app_db):
    db, _ = app_db
    conn = server.get_db()
    try:
        now = time.time()
        assert server._try_acquire_pair_lock(conn, PK, "tok-1", "перво", now) is True
        assert server._try_acquire_pair_lock(conn, PK, "tok-2", "второй", now + 1) is False, \
            "живой лок перезахватить нельзя"
        server._release_pair_lock(conn, PK, "tok-2")
        assert conn.execute(
            "SELECT 1 FROM pending_pairs WHERE pair_key = ?", (PK,)
        ).fetchone(), "чужим токеном лок не снимается (U5-fix)"
        server._release_pair_lock(conn, PK, "tok-1")
        assert server._try_acquire_pair_lock(conn, PK, "tok-3", "второй", now + 2) is True, \
            "после освобождения пара снова захватываема"
        server._release_pair_lock(conn, PK, "tok-3")
        assert _pending_count(conn) == 0
    finally:
        conn.close()


def test_expired_lock_is_reacquirable_by_exactly_one(app_db):
    db, _ = app_db
    conn = server.get_db()
    stale = time.time() - server.LOCK_TTL - 10
    conn.execute(
        "INSERT INTO pending_pairs (pair_key, state, lock_ts, owner, attempted_by)"
        " VALUES (?, 'locked', ?, 'сбой', 'сбой')", (PK, stale),
    )
    conn.commit()
    conn.close()
    barrier = threading.Barrier(2)
    wins = []
    wlock = threading.Lock()

    def racer(tag):
        cc = server.get_db()
        now = time.time()
        barrier.wait(timeout=5)
        got = server._try_acquire_pair_lock(cc, PK, f"tok-{tag}", tag, now)
        with wlock:
            if got:
                wins.append(tag)
        cc.close()

    ths = [threading.Thread(target=racer, args=(t,)) for t in ("x", "y")]
    [t.start() for t in ths]
    [t.join(timeout=5) for t in ths]
    assert wins == ["x"] or wins == ["y"], wins  # ровно один перезахватил протухший лок


# --- T08.2: никаких «могил» в pending_pairs ---------------------------------

def test_rate_limited_leaves_no_lock(app_db, monkeypatch):
    db, stub = app_db
    monkeypatch.setattr(server, "_admit_experiment",
                        lambda conn, device_id: (False, "Дневной лимит исчерпан."))
    resp = server.discover(_req("gold", "fire"))
    assert resp.ok is False and resp.status == "rate_limited"
    conn = sqlite3.connect(db)
    assert _pending_count(conn) == 0
    assert stub.generate_calls == []
    conn.close()


def test_validation_reject_leaves_no_tombstone(app_db):
    """«Мусорный» запрос (несуществующий ингредиент → 400) не оставляет строку:
    раньше finally писал state='resolved' навечно (T08.2)."""
    db, _ = app_db
    with pytest.raises(server.HTTPException) as ei:
        server.discover(_req("gold", "bogusslug"))
    assert ei.value.status_code == 400
    conn = sqlite3.connect(db)
    assert _pending_count(conn) == 0
    conn.close()


def test_startup_purge_removes_legacy_tombstones(app_db):
    db, _ = app_db
    conn = server.get_db()
    now = time.time()
    conn.execute("INSERT INTO pending_pairs (pair_key, state, lock_ts, owner) "
                 "VALUES ('a|b','resolved',?,'никто')", (now,))
    conn.execute("INSERT INTO pending_pairs (pair_key, state, lock_ts, owner) VALUES ('c|d','locked',?,'сбой')",
                 (now - server.LOCK_TTL - 1,))
    conn.execute("INSERT INTO pending_pairs (pair_key, state, lock_ts, owner) VALUES ('e|f','locked',?,'живой')",
                 (now,))
    conn.commit()
    conn.close()
    asyncio.run(server.startup())  # идемпотентен: init_db + зачистка
    conn = server.get_db()
    rows = {r["pair_key"]: r["state"] for r in
            conn.execute("SELECT pair_key, state FROM pending_pairs").fetchall()}
    conn.close()
    assert rows == {"e|f": "locked"}, "сдохшие локи и resolved-могилы зачищаются, живые — нет"


# --- T08.3: _ensure_challenge идемпотентен под гонкой -----------------------

def test_ensure_challenge_concurrent_no_500(app_db, monkeypatch):
    db, _ = app_db
    monkeypatch.setattr(server, "_today", lambda: "2099-12-31")
    errors = []
    results = []
    rlock = threading.Lock()
    barrier = threading.Barrier(8)

    def racer():
        try:
            cc = server.get_db()
            barrier.wait(timeout=5)
            ch = server._ensure_challenge(cc)
            cc.close()
            with rlock:
                results.append(ch)
        except Exception as e:  # noqa: BLE001
            with rlock:
                errors.append(e)

    ths = [threading.Thread(target=racer) for _ in range(8)]
    [t.start() for t in ths]
    [t.join(timeout=10) for t in ths]
    assert not errors, f"гонка за первый запрос дня не должна давать 500: {errors}"
    assert len({r["id"] for r in results}) == 1
    conn = sqlite3.connect(db)
    assert conn.execute("SELECT COUNT(*) FROM challenges WHERE day='2099-12-31'").fetchone()[0] == 1
    conn.close()


# --- T04+T08: letters под потоками (новый класс гонок после перевода в def) -

def test_concurrent_letter_today_single_row_no_500(app_db):
    db, stub = app_db
    barrier = threading.Barrier(2)
    outcomes = {}

    def reader(tag):
        barrier.wait(timeout=5)
        try:
            outcomes[tag] = server.letter_today(device_id="dev-letter")
        except Exception as e:  # noqa: BLE001
            outcomes[tag] = e

    ths = [threading.Thread(target=reader, args=(t,)) for t in ("l", "r")]
    [t.start() for t in ths]
    [t.join(timeout=15) for t in ths]
    assert all(not isinstance(v, Exception) for v in outcomes.values()), outcomes
    for resp in outcomes.values():
        assert resp.today is not None
    # письмо на день одно; текст у обоих ответов — победителя гонки вставки
    assert outcomes["l"].today.hint == outcomes["r"].today.hint
    conn = sqlite3.connect(db)
    n = conn.execute("SELECT COUNT(*) FROM letters WHERE device_id = 'dev-letter'").fetchone()[0]
    conn.close()
    assert n == 1, "PK (device_id, day): две гонки не должны дать два письма"
    assert stub.hint_calls, "генерация всё же была"
