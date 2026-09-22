"""
Тесты гибридной генерации: LLM-путь, отказ («туман») и недоступность модели.

Сервер в тестах запускается с LLM_PROVIDER=mock (см. conftest), поэтому
«модель» детерминирована и не требует сети: для неизвестной пары она создаёт
вещество, а пара person|gold моделирует несочетаемую пару.
"""

import os
import sys

import requests

BASE_URL = "http://localhost:8080/api"


def _discover(a, b, nick="Игрок", device_id="device-1"):
    return requests.post(
        f"{BASE_URL}/discover",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=30,
    )


def _brew_check(a, b, nick="Игрок", device_id="device-1"):
    return requests.post(
        f"{BASE_URL}/brew-check",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=30,
    )


class TestLlmGeneration:
    """LLM-путь создания нового вещества."""

    def test_unknown_pair_created_with_llm(self, server):
        resp = _discover("dust", "glass", nick="ЛЛМ", device_id="device-llm")
        assert resp.status_code in (200, 201)
        data = resp.json()
        assert data["ok"] is True
        assert data["status"] == "created"
        assert data["already_known"] is False
        assert data["discovery"]["gen_method"] == "llm"
        assert data["discovery"]["name"]
        assert data["discovery"]["category"] in ("огонь", "вода", "земля", "воздух")
        assert data["discovery"]["color"].startswith("#")

    def test_repeat_discovery_is_deterministic_and_shared(self, server):
        r1 = _discover("stone", "mist", nick="А", device_id="d-a")
        r2 = _discover("stone", "mist", nick="Б", device_id="d-b")
        assert r1.json()["discovery"]["slug"] == r2.json()["discovery"]["slug"]
        assert r2.json()["discovery"]["author"] == "А"


class TestNotCombinable:
    """Пары, которые модель считает бессмысленными («туман»)."""

    def test_not_combinable_pair_returns_tuman(self, server):
        resp = _discover("person", "gold", nick="Туман", device_id="device-fog")
        assert resp.status_code in (200, 201)
        data = resp.json()
        assert data["status"] == "not_combinable"
        assert data["discovery"] is None
        assert "Туман" in data["message"]

    def test_not_combinable_is_cached_across_players(self, server):
        r1 = _discover("person", "gold", nick="А", device_id="d-a")
        r2 = _discover("person", "gold", nick="Б", device_id="d-b")
        assert r1.json()["status"] == "not_combinable"
        assert r2.json()["status"] == "not_combinable"

    def test_brew_check_reports_not_combinable(self, server):
        bc = _brew_check("gold", "person", nick="В", device_id="d-c")
        assert bc.status_code == 200
        data = bc.json()
        assert data["found"] is False
        assert data["status"] == "not_combinable"


class TestFallback:
    """При недоступной модели решение НЕ выдумывается и НЕ фиксируется."""

    def _srv(self, tmp_path, monkeypatch):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv
        monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "fallback.db"))
        srv.init_db()
        return srv

    def test_llm_unavailable_returns_unavailable(self, tmp_path, monkeypatch):
        """LLM недоступна → ("unavailable", None), ничего не сохраняется."""
        srv = self._srv(tmp_path, monkeypatch)
        conn = srv.get_db()

        class Off:
            def available(self):
                return True

            def generate(self, *a, **k):
                raise srv.LLMError("offline")

        kind, discovery = srv._generate_for_pair(
            conn, "fire", "glass", "fire|glass", "Тест", llm=Off()
        )
        assert kind == "unavailable"
        assert discovery is None
        # в БД не появилось ни элемента, ни отказа
        n = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        assert n == 57
        assert conn.execute("SELECT 1 FROM rejected_pairs WHERE pair_key='fire|glass'").fetchone() is None
        conn.close()

    def test_unavailable_pair_can_be_generated_later(self, tmp_path, monkeypatch):
        """Решение не фиксируется: после «unavailable» пара остаётся кандидатом,
        и когда модель возвращается — успешно создаётся."""
        import os
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv
        from fastapi.testclient import TestClient

        state = {"down": True}

        class Flaky:
            def available(self):
                return True

            def generate(self, *a, **k):
                if state["down"]:
                    raise srv.LLMError("offline")
                return {"combinable": True, "name": "Горнило"}

        monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "flaky.db"))
        monkeypatch.setattr(srv, "get_llm", lambda: Flaky())
        client = TestClient(srv.app)
        with client:
            r1 = client.post("/api/discover", json={"a": "fire", "b": "glass", "nick": "А", "device_id": "d1"})
            assert r1.json()["status"] == "unavailable"
            # пара не сохранена как rejected → повторно кандидат
            bc = client.post("/api/brew-check", json={"a": "fire", "b": "glass", "nick": "А", "device_id": "d1"})
            assert bc.json()["status"] == "candidate"
            # модель вернулась → создаётся
            state["down"] = False
            r2 = client.post("/api/discover", json={"a": "fire", "b": "glass", "nick": "А", "device_id": "d1"})
            assert r2.json()["status"] == "created"
            assert r2.json()["discovery"]["name"] == "Горнило"



class TestContractAndSemantics:
    """Новый контракт: LLM отвечает только {combinable, name}; семантика — отдельным этапом."""

    def test_validate_result_is_technical_only(self):
        from gen_llm import validate_result
        assert validate_result({"combinable": True, "name": "Дом"}) == {"combinable": True, "name": "Дом"}
        assert validate_result({"combinable": False}) == {"combinable": False}
        # без кириллицы — невалидно
        assert validate_result({"combinable": True, "name": "Cat"}) is None
        # цифры / дефисы — невалидно
        assert validate_result({"combinable": True, "name": "Дом2"}) is None
        assert validate_result({"combinable": True, "name": "Дом-замок"}) is None
        # лишние поля игнорируются (category/glyph больше не требуются)
        assert validate_result({"combinable": True, "name": "Дом", "category": "земля"})["name"] == "Дом"

    def test_semantic_check_guardrails(self):
        from gen_llm import semantic_check
        ok, _ = semantic_check("Дом", "Кирпич", "Кирпич")
        assert ok
        ok, _ = semantic_check("Камень", "Камень", "Камень")
        assert not ok  # результат == ингредиент
        ok, reason = semantic_check("ПыльСтекло", "Пыль", "Стекло")
        assert not ok and "склейк" in reason
        ok, reason = semantic_check("Пыль Стекло", "Пыль", "Стекло")
        assert not ok  # склейка с пробелом

    def test_mock_obvious_and_nonsense(self):
        from gen_llm import LLMGenerator
        g = LLMGenerator(provider="mock")
        r = g.generate("wall", "wall", "Стена", "Стена", "wall|wall")
        assert r == {"combinable": True, "name": "Дом"}
        r = g.generate("person", "gold", "Человек", "Золото", "gold|person")
        assert r == {"combinable": False}
        # Камень+Камень не должен давать «Кота» (заглушка даёт детерминированное имя)
        r = g.generate("stone", "stone", "Камень", "Камень", "stone|stone")
        assert r["combinable"] is True and r["name"] != "Кот"


class TestDbIsSourceOfTruth:
    """БД — источник истины: сгенерированный/отклонённый результат не пересчитывается."""

    def _client(self, tmp_path, monkeypatch, fake_llm):
        import os
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv
        from fastapi.testclient import TestClient

        monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "truth.db"))
        monkeypatch.setattr(srv, "get_llm", lambda: fake_llm)
        return TestClient(srv.app)

    def test_created_pair_is_not_regenerated(self, tmp_path, monkeypatch):
        calls = {"n": 0}

        class FakeLLM:
            def available(self):
                return True

            def generate(self, *a, **k):
                calls["n"] += 1
                return {"combinable": True, "name": "ТестоваяВещь"}

        client = self._client(tmp_path, monkeypatch, FakeLLM())
        with client:
            r1 = client.post("/api/discover", json={"a": "dust", "b": "sky", "nick": "А", "device_id": "d1"})
            assert r1.status_code == 200 and r1.json()["status"] == "created"
            r2 = client.post("/api/discover", json={"a": "dust", "b": "sky", "nick": "Б", "device_id": "d2"})
            assert r2.status_code == 200 and r2.json()["status"] == "known"
            # LLM вызвана ровно один раз
            assert calls["n"] == 1

    def test_rejected_pair_is_saved_and_not_regenerated(self, tmp_path, monkeypatch):
        calls = {"n": 0}

        class FakeLLM:
            def available(self):
                return True

            def generate(self, *a, **k):
                calls["n"] += 1
                return {"combinable": False}

        client = self._client(tmp_path, monkeypatch, FakeLLM())
        with client:
            r1 = client.post("/api/discover", json={"a": "sand", "b": "smoke", "nick": "А", "device_id": "d1"})
            assert r1.status_code == 200 and r1.json()["status"] == "not_combinable"
            r2 = client.post("/api/discover", json={"a": "sand", "b": "smoke", "nick": "Б", "device_id": "d2"})
            assert r2.status_code == 200 and r2.json()["status"] == "not_combinable"
            bc = client.post("/api/brew-check", json={"a": "sand", "b": "smoke", "nick": "В", "device_id": "d3"})
            assert bc.json()["status"] == "not_combinable"
            # отказ сохранён в БД, модель вызвана ровно один раз
            assert calls["n"] == 1

    def test_generation_exhaustion_returns_rejected(self, tmp_path, monkeypatch):
        """Кандидат отклонён → combinable:false → пара сохраняется как rejected."""
        import os
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv

        class BadLLM:
            def available(self):
                return True

            def generate(self, *a, **k):
                return {"combinable": False}

        monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "exh.db"))
        srv.init_db()
        conn = srv.get_db()
        kind, discovery = srv._generate_for_pair(conn, "sand", "smoke", "sand|smoke", "Тест", llm=BadLLM())
        assert kind == "not_combinable"
        assert discovery is None
        conn.close()
