"""Регрессии квоты LLM: квота резервируется по ФАКТУ генерации, а не по
клиентскому флагу experiment (обход «experiment:false» закрыт); при отказе
модели квота возвращается; письма — отдельный дневной бюджет per-device+global;
атлас (третий оракул, _ensure_atlas) — мировой бюджет под ключом "" с теми же
возвратами резерва при LLMError/пустом намёке.

NOTE: тесты написаны в стиле test_experiment_limits.py (TestClient, monkeypatch
констант сервера). На машине разработки не запускались (нет fastapi, py<3.10);
прогон — в задаче T09.
"""

import os
import sys


def _client(tmp_path, monkeypatch, llm):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    from fastapi.testclient import TestClient

    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "quota.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    srv.init_db()
    return srv, TestClient(srv.app)


class _ExternalLLM:
    provider = "openrouter"

    def __init__(self):
        self.calls = 0
        self.hint_calls = 0
        self.names = iter(["ПерваяВещь", "ВтораяВещь", "ТретьяВещь", "ЧетвёртаяВещь"])

    def available(self):
        return True

    def generate(self, *args, **kwargs):
        self.calls += 1
        return {"combinable": True, "name": next(self.names)}

    def generate_hint(self, *args, **kwargs):
        self.hint_calls += 1
        return {"hint": "Там, где солнце встречает песок."}


class _DownLLM(_ExternalLLM):
    """Внешний провайдер, у которого генерация всегда падает (LLMError)."""

    def generate(self, *args, **kwargs):
        self.calls += 1
        raise self._error()

    def generate_hint(self, *args, **kwargs):
        self.hint_calls += 1
        raise self._error()

    @staticmethod
    def _error():
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        from gen_llm import LLMError
        return LLMError("модель недоступна")


class _EmptyHintLLM(_ExternalLLM):
    """Внешний провайдер, который отвечает, но намёк всегда пустой."""

    def generate_hint(self, *args, **kwargs):
        self.hint_calls += 1
        return {"hint": "   "}


def _experiment_tuned(srv, monkeypatch, daily=1, cooldown=0.0, global_daily=100):
    """Понятные детерминированные лимиты экспериментов (без реальных 5 сек/200)."""
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", daily)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", cooldown)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", global_daily)


def _letter_tuned(srv, monkeypatch, daily=3, cooldown=0.0, global_daily=100):
    monkeypatch.setattr(srv, "LETTER_DAILY_LIMIT", daily)
    monkeypatch.setattr(srv, "LETTER_COOLDOWN_SEC", cooldown)
    monkeypatch.setattr(srv, "LETTER_GLOBAL_DAILY_LIMIT", global_daily)


def _atlas_tuned(srv, monkeypatch, daily=100, cooldown=0.0):
    """Атлас — мировой бюджет под ключом "" (одна страница на весь сервер)."""
    monkeypatch.setattr(srv, "ATLAS_DAILY_LIMIT", daily)
    monkeypatch.setattr(srv, "ATLAS_COOLDOWN_SEC", cooldown)


def _atlas_attempts(srv):
    row = srv.get_db().execute(
        "SELECT attempts FROM atlas_limits WHERE device_id = ?", ("",)
    ).fetchone()
    return int(row["attempts"]) if row else 0


class TestQuotaKeysOnGenerationFact:
    def test_flag_false_does_not_bypass_device_quota(self, tmp_path, monkeypatch):
        """Обход из брифа: experiment:false на заведомо новых парах всё равно
        упирается в дневной лимит — квота ключуется фактом генерации."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _experiment_tuned(srv, monkeypatch, daily=1)
        with client:
            first = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1",
                "experiment": False,
            })
            assert first.json()["status"] == "created"
            second = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "device-1",
                "experiment": False,
            })
            assert second.json()["status"] == "rate_limited"
            # LLM не должна вызываться сверх квоты, даже когда флаг снят
            assert llm.calls == 1

    def test_rate_limited_response_shape_is_preserved(self, tmp_path, monkeypatch):
        """Форма rate_limited не меняется — старые клиенты не ломаются."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _experiment_tuned(srv, monkeypatch, daily=1)
        with client:
            client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1",
            })
            limited = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "device-1",
            })
        body = limited.json()
        assert limited.status_code == 200
        assert body["ok"] is False
        assert body["status"] == "rate_limited"
        assert body["discovery"] is None
        assert body["already_known"] is False
        assert isinstance(body["message"], str) and body["message"]

    def test_cached_pair_still_costs_nothing(self, tmp_path, monkeypatch):
        """Известная пара отвечает до резерва: кэш квоту не расходует."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _experiment_tuned(srv, monkeypatch, daily=1)
        with client:
            first = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1",
            })
            assert first.json()["status"] == "created"
            known = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "B", "device_id": "device-2",
                "experiment": False,
            })
            assert known.json()["status"] == "known"
            row = srv.get_db().execute(
                "SELECT attempts FROM experiment_limits WHERE device_id = ?", ("device-2",)
            ).fetchone()
            assert row is None
            assert llm.calls == 1

    def test_unavailable_generation_refunds_quota(self, tmp_path, monkeypatch):
        """unavailable не должен сжигать квоту: после возврата лимита следующая
        пара генерируется, когда модель вернулась."""
        down = _DownLLM()
        srv, client = _client(tmp_path, monkeypatch, down)
        _experiment_tuned(srv, monkeypatch, daily=1)
        with client:
            failed = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1",
            })
            assert failed.json()["status"] == "unavailable"
            row = srv.get_db().execute(
                "SELECT attempts FROM experiment_limits WHERE device_id = ?", ("device-1",)
            ).fetchone()
            assert row is not None and int(row["attempts"]) == 0
            # чиним модель — та же пара снова кандидат и проходит по квоте
            good = _ExternalLLM()
            monkeypatch.setattr(srv, "get_llm", lambda: good)
            retried = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1",
            })
            assert retried.json()["status"] == "created"
            row = srv.get_db().execute(
                "SELECT attempts FROM experiment_limits WHERE device_id = ?", ("device-1",)
            ).fetchone()
            assert int(row["attempts"]) == 1


class TestLetterQuota:
    def test_new_device_spam_hits_global_letter_cap(self, tmp_path, monkeypatch):
        """Спам /api/letter/today с новыми device_id упирается в мировой
        дневной лимит писем (квота экспериментов здесь ни при чём)."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _letter_tuned(srv, monkeypatch, daily=3, global_daily=2)
        with client:
            l1 = client.get("/api/letter/today", params={"device_id": "dev-1"})
            l2 = client.get("/api/letter/today", params={"device_id": "dev-2"})
            l3 = client.get("/api/letter/today", params={"device_id": "dev-3"})
        assert l1.json()["today"] is not None
        assert l2.json()["today"] is not None
        # третий — мягкий отказ: письмо отсутствует, ответа из LLM нет
        assert l3.json()["today"] is None
        assert l3.json()["ok"] is True
        assert llm.hint_calls == 2

    def test_letter_device_daily_cap_blocks_generation(self, tmp_path, monkeypatch):
        """Пер-девайсный дневной лимит писем блокирует генерацию до вызова LLM."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _letter_tuned(srv, monkeypatch, daily=1, global_daily=100)
        with client:
            conn = srv.get_db()
            conn.execute(
                "INSERT INTO letter_limits(day, device_id, attempts, last_at) "
                "VALUES (?, ?, 1, 0)",
                (srv._today(), "dev-capped"),
            )
            conn.commit()
            conn.close()
            limited = client.get("/api/letter/today", params={"device_id": "dev-capped"})
        assert limited.json()["today"] is None
        assert llm.hint_calls == 0

    def test_letter_quota_refunded_when_hint_fails(self, tmp_path, monkeypatch):
        """Отказ генерации намёка возвращает резерв: письмо не сжигает лимит."""
        down = _DownLLM()
        srv, client = _client(tmp_path, monkeypatch, down)
        _letter_tuned(srv, monkeypatch, daily=1, global_daily=100)
        with client:
            failed = client.get("/api/letter/today", params={"device_id": "dev-1"})
            assert failed.json()["today"] is None
            row = srv.get_db().execute(
                "SELECT attempts FROM letter_limits WHERE device_id = ?", ("dev-1",)
            ).fetchone()
            assert row is not None and int(row["attempts"]) == 0
            good = _ExternalLLM()
            monkeypatch.setattr(srv, "get_llm", lambda: good)
            ok = client.get("/api/letter/today", params={"device_id": "dev-1"})
            assert ok.json()["today"] is not None
            assert good.hint_calls == 1

    def test_letter_cap_is_separate_from_experiment_cap(self, tmp_path, monkeypatch):
        """Исчерпанная квота экспериментов не блокирует письма (разные бюджеты)."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _experiment_tuned(srv, monkeypatch, daily=1)
        _letter_tuned(srv, monkeypatch, daily=3, global_daily=100)
        with client:
            client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "dev-1",
            })
            limited = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "dev-1",
            })
            assert limited.json()["status"] == "rate_limited"
            letter = client.get("/api/letter/today", params={"device_id": "dev-1"})
            assert letter.json()["today"] is not None


class TestAtlasQuota:
    """Регресс третьего оракула: _ensure_atlas без квоты при пустом намёке или
    LLMError заставлял каждый запрос к /api/atlas/today молотить generate_hint."""

    def test_failure_loop_capped_by_cooldown(self, tmp_path, monkeypatch):
        """Цикл отказных генераций: кулдаун гасит молотилку, LLM — ровно 1 вызов."""
        down = _DownLLM()
        srv, client = _client(tmp_path, monkeypatch, down)
        _atlas_tuned(srv, monkeypatch, daily=100, cooldown=3600.0)
        with client:
            for _ in range(5):
                r = client.get("/api/atlas/today")
                assert r.json()["today"] is None
        assert down.hint_calls == 1
        # возврат резерва не сбрасывает last_at: кулдаун продолжает работать
        assert _atlas_attempts(srv) == 0

    def test_atlas_cap_blocks_generation_before_llm(self, tmp_path, monkeypatch):
        """Исчерпанный мировой лимит атласа не доходит до LLM."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _atlas_tuned(srv, monkeypatch, daily=1, cooldown=0.0)
        with client:
            conn = srv.get_db()
            conn.execute(
                "INSERT INTO atlas_limits(day, device_id, attempts, last_at) "
                "VALUES (?, ?, 1, 0)",
                (srv._today(), ""),
            )
            conn.commit()
            conn.close()
            r = client.get("/api/atlas/today")
        assert r.json()["today"] is None
        assert llm.hint_calls == 0

    def test_empty_hint_refunds_quota_and_retry_succeeds(self, tmp_path, monkeypatch):
        """Пустой намёк — страница не фиксируется, резерв возвращается, ретрай проходит."""
        empty = _EmptyHintLLM()
        srv, client = _client(tmp_path, monkeypatch, empty)
        _atlas_tuned(srv, monkeypatch, daily=1, cooldown=0.0)
        with client:
            r = client.get("/api/atlas/today")
            assert r.json()["today"] is None
            assert srv.get_db().execute(
                "SELECT COUNT(*) AS c FROM atlas_pages"
            ).fetchone()["c"] == 0
            assert _atlas_attempts(srv) == 0
            good = _ExternalLLM()
            monkeypatch.setattr(srv, "get_llm", lambda: good)
            ok = client.get("/api/atlas/today")
            assert ok.json()["today"] is not None
            assert good.hint_calls == 1
            # успешная генерация списывает ровно одну попытку мирового бюджета
            assert _atlas_attempts(srv) == 1

    def test_llm_error_refunds_quota_and_retry_succeeds(self, tmp_path, monkeypatch):
        """LLMError в атласе возвращает резерв, как на пути писем."""
        down = _DownLLM()
        srv, client = _client(tmp_path, monkeypatch, down)
        _atlas_tuned(srv, monkeypatch, daily=1, cooldown=0.0)
        with client:
            r = client.get("/api/atlas/today")
            assert r.json()["today"] is None
            assert _atlas_attempts(srv) == 0
            good = _ExternalLLM()
            monkeypatch.setattr(srv, "get_llm", lambda: good)
            ok = client.get("/api/atlas/today")
            assert ok.json()["today"] is not None
            assert good.hint_calls == 1

    def test_cached_atlas_page_costs_nothing(self, tmp_path, monkeypatch):
        """Кэш страницы дня не расходует квоту и не зовёт LLM повторно."""
        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        _atlas_tuned(srv, monkeypatch, daily=1, cooldown=0.0)
        with client:
            first = client.get("/api/atlas/today")
            assert first.json()["today"] is not None
            for _ in range(3):
                again = client.get("/api/atlas/today")
                assert again.json()["today"] is not None
        assert llm.hint_calls == 1
        assert _atlas_attempts(srv) == 1
