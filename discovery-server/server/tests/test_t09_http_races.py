"""T09/U8: HTTP-гонки, health под нагрузкой и e2e-флиш дневной шкалы.

Почему живой uvicorn in-process, а не TestClient: TestClient сериализует
запросы между потоками (один portal), и настоящую гонку на /api/discover им
не поймать. Здесь же поднимается НАСТОЯЩИЙ uvicorn.Server в потоке (порт,
выданный ОС; прод-порт 8080 запрещён conftest-ассертом), event loop работает,
sync-хендлер discover уходит в threadpool, а фейковая LLM управляется
threading.Event — гонка детерминирована: победитель «зависает» в генерации,
проигравшие приходят, пока лок жив.

Фейковая LLM отдаётся через monkeypatch srv._LLM_GEN (тот же хук, что в
test_u5_concurrency: get_llm() возвращает синглтон, если он задан).
provider="mock" — серверная квота внешних вызовов не тратится.

Адрес строится ТОЛЬКО из фикстуры. Переменные окружения SERVER_URL /
TEST_SERVER_URL тесты не читают намеренно (решение T09): подмена адреса из
ENV — это канал, через который тесты уезжали на прод-порт.

Флиш временной шкалы (U7) — документированный подход: _now_dt — единственная
точка серверного времени, модульный глобал, читаемый в момент вызова, поэтому
её рантайм-подмена даёт детерминированный e2e-переход границы дня без спавна
процесса и без ожидания полуночи. Попутно stdlib-харнесс
harness_time_scale_u7.py доказывает то же на SQL-копиях.
"""
import os
import socket
import sqlite3
import sys
import threading
import time
import urllib.request
from datetime import datetime, timedelta

import pytest

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

server = pytest.importorskip("server")  # fastapi + py3.10; на 3.9 — честная ошибка сборки

PK = "fire|gold"  # обе слаги в стартовом графе, рецепта нет — свежая пара (см. test_u5_concurrency)


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    assert port != 8080, "прод-порт 8080 тестам занят нельзя"
    return port


class _GatedLLM:
    """Первый generate() становится на место и ждёт release-события.

    Так победитель гонки Держит слот threadpool и лок пары ровно столько,
    сколько нужно тесту, — проигравшие гарантированно приходят в живую
    блокировку, а health-проверка — в момент занятости воркера.
    """

    provider = "mock"  # внешняя LLM-квота не тратится
    models = []
    api_key = ""

    def __init__(self, name: str = "Гиперпереход"):
        self.release = threading.Event()
        self.entered = threading.Event()
        self.name = name
        self._lock = threading.Lock()
        self.generate_calls = []

    def available(self):
        return True

    def generate(self, a_slug, b_slug, a_name, b_name, pair_key):
        with self._lock:
            self.generate_calls.append(pair_key)
        self.entered.set()
        assert self.release.wait(timeout=30), "тест не отпустил фейковую LLM"
        return {"combinable": True, "name": self.name,
                "glyph": "", "description": "", "tag": ""}


@pytest.fixture(scope="module")
def live_api(tmp_path_factory):
    """Настоящий uvicorn в потоке: ephemeral-порт, lifespan=он (init_db на
    старте), остановка should_exit+join (без pkill — Windows-safe)."""
    uvicorn = pytest.importorskip("uvicorn")
    port = _free_port()
    db = str(tmp_path_factory.mktemp("livehttp") / "live.db")

    old_db, old_gen = server.DB_PATH, server._LLM_GEN
    server.DB_PATH = db
    config = uvicorn.Config(server.app, host="127.0.0.1", port=port,
                            log_level="warning")
    srv = uvicorn.Server(config)
    th = threading.Thread(target=srv.run, daemon=True)
    th.start()
    base = f"http://127.0.0.1:{port}/api"
    deadline = time.time() + 30
    up = False
    while time.time() < deadline and not up:
        try:
            with urllib.request.urlopen(f"{base}/health", timeout=2) as r:
                up = r.status == 200
        except OSError:
            time.sleep(0.2)
    try:
        assert up, f"live-сервер не поднялся на порту {port}"
        yield base
    finally:
        srv.should_exit = True
        th.join(timeout=10)
        server.DB_PATH = old_db
        server._LLM_GEN = old_gen


@pytest.fixture()
def fresh_live_db(live_api, tmp_path, monkeypatch):
    """Отдельная чистая БД на каждый тест (сервер общий): гонки/health не
    зависят от порядка запуска и друг от друга."""
    db = str(tmp_path / "per-test.db")
    monkeypatch.setattr(server, "DB_PATH", db)
    server.init_db()
    return live_api


def _post_discover(base, a, b, nick, device, timeout=40):
    import requests
    return requests.post(
        f"{base}/discover",
        json={"a": a, "b": b, "nick": nick, "device_id": device},
        timeout=timeout,
    )


class TestParallelDiscoverHttp:
    """spec.md:321: N параллельных /api/discover одной новой пары —
    ровно ОДНА генерация, проигравшие — 409-or-known (wire-формы T05/U6)."""

    def test_n_concurrent_one_generation_rest_409_or_known(self, fresh_live_db, monkeypatch):
        base = fresh_live_db
        fake = _GatedLLM()
        monkeypatch.setattr(server, "_LLM_GEN", fake)

        winner_out = {}
        losers_out = {}

        def brew(tag, a, b):
            r = _post_discover(base, a, b, nick=f"Гонщик{tag}", device=f"race-{tag}")
            (winner_out if tag == "0" else losers_out)[tag] = r

        th0 = threading.Thread(target=brew, args=("0", "fire", "gold"))
        th0.start()
        try:
            # победитель вошёл в генерацию ⇒ лок пары точно жив:
            assert fake.entered.wait(timeout=15), "победитель не дошёл до генерации"

            losers = [threading.Thread(target=brew, args=(str(i), "fire", "gold"))
                      for i in (1, 2, 3)]
            for t in losers:
                t.start()
            for t in losers:
                t.join(timeout=30)
            assert len(losers_out) == 3, "проигравшие не получили ответ (висячий запрос)"

            for tag, r in losers_out.items():
                if r.status_code == 409:
                    # wire U5/U6: живой лок пары
                    assert "Пара в обработке" in r.json()["detail"], r.text
                else:
                    assert r.status_code == 200, f"{tag}: {r.status_code} {r.text}"
                    assert r.json()["status"] in ("known", "created"), r.text

            fake.release.set()
            th0.join(timeout=30)
            w = winner_out.get("0")
            assert w is not None and w.status_code == 200, f"победитель: {w}"
            assert w.json()["status"] == "created"
            # ровно одна генерация на всю гонку (4 запроса)
            assert fake.generate_calls == [PK], fake.generate_calls

            conn = sqlite3.connect(str(server.DB_PATH))
            try:
                n_recipes = conn.execute(
                    "SELECT COUNT(*) FROM recipes WHERE pair_key = ?", (PK,)
                ).fetchone()[0]
                n_locks = conn.execute("SELECT COUNT(*) FROM pending_pairs").fetchone()[0]
            finally:
                conn.close()
            assert n_recipes == 1
            assert n_locks == 0, "после гонки очередей лока не остаётся"
        finally:
            # тот же паттерн, что в health-тесте: любой упавший assert между
            # входом победителя и release не должен оставлять воркер
            # «припаркованным» на 30 секунд и th0 — неjoinнутым (set идемпотентен)
            fake.release.set()
            th0.join(timeout=30)


class TestHealthUnderLoad:
    """U8 carried (f): /api/health отвечает, пока медленная генерация держит
    воркер threadpool (async health + sync discover — разные пулы исполнения)."""

    def test_health_answers_while_generation_occupies_worker(self, fresh_live_db, monkeypatch):
        base = fresh_live_db
        fake = _GatedLLM(name="Гиперпроба")
        monkeypatch.setattr(server, "_LLM_GEN", fake)

        th = threading.Thread(
            target=lambda: _post_discover(base, "fire", "gold", "Здоровяк", "health-dev"))
        th.start()
        assert fake.entered.wait(timeout=15), "генерация не стартовала"
        try:
            t0 = time.monotonic()
            with urllib.request.urlopen(f"{base}/health", timeout=5) as r:
                body = r.read().decode("utf-8")
                status = r.status
            elapsed = time.monotonic() - t0
            assert status == 200, body
            assert '"ok":true' in body.replace(" ", ""), body
            assert elapsed < 5.0, f"healthFrozen под нагрузкой: {elapsed:.1f}s"
        finally:
            fake.release.set()
            th.join(timeout=30)


class TestTimeScaleE2EFlip:
    """U7 e2e: смена серверного времени одним monkeypatch srv._now_dt
    переворачивает И дневной ключ, и цель дня на реальном HTTP-стеке
    (TestClient → _ensure_challenge → БД)."""

    def test_day_key_and_target_flip_together(self, tmp_path, monkeypatch):
        from fastapi.testclient import TestClient

        day_a = datetime(2026, 9, 23, 12, 0)
        day_b = day_a + timedelta(days=1, seconds=1)
        clock = {"now": day_a}
        monkeypatch.setattr(server, "DB_PATH", str(tmp_path / "flip.db"))
        monkeypatch.setattr(server, "_now_dt", lambda: clock["now"])
        server.init_db()
        client = TestClient(server.app)

        c1 = client.get("/api/challenge").json()
        assert c1["day"] == "2026-09-23"
        assert c1["target"] == server._challenge_target_for("2026-09-23")

        clock["now"] = day_b
        c2 = client.get("/api/challenge").json()
        assert c2["day"] == "2026-09-24"
        assert c2["target"] == server._challenge_target_for("2026-09-24")
        # даты выбраны так, что цель реально меняется (23-е: ice, 24-е: boat);
        # без этого ассерта тест проходил бы и на «залипшей» цели
        assert c2["target"] != c1["target"], (c1["target"], c2["target"])

        conn = server.get_db()
        try:
            days = [r["day"] for r in conn.execute(
                "SELECT day FROM challenges ORDER BY day").fetchall()]
        finally:
            conn.close()
        assert days == ["2026-09-23", "2026-09-24"], \
            "перевернулась ровно одна дата, старый день не перетёрт"
