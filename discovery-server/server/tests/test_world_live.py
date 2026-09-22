"""
Тесты «живого мира»: лента событий первооткрытий и ежедневная цель-гонка.

In-process (TestClient + FakeLLM), чтобы детерминированно проверять победу
в ежедневной цели без сети и без реальной LLM.
"""

import os
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch, fake_llm=None):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "live.db"))
    if fake_llm is not None:
        monkeypatch.setattr(srv, "get_llm", lambda: fake_llm)
    return srv


class FakeOK:
    def __init__(self, name="Свежее"):
        self.name = name

    def available(self):
        return True

    def generate(self, *a, **k):
        return {"combinable": True, "name": self.name}


class TestEvents:
    def test_events_recorded_on_discovery(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeOK())
        client = TestClient(srv.app)
        with client:
            r = client.post("/api/discover", json={"a": "dust", "b": "sky", "nick": "Варда", "device_id": "d1"})
            assert r.json()["status"] == "created"
            ev = client.get("/api/events").json()
            assert ev["ok"] is True
            names = [e["out_name"] for e in ev["events"]]
            assert "Свежее" in names
            e0 = ev["events"][0]
            assert e0["discoverer"] == "Варда"
            assert e0["a"] in ("dust", "sky") and e0["b"] in ("dust", "sky")

    def test_known_pair_does_not_create_event(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeOK())
        client = TestClient(srv.app)
        with client:
            # fire+water — уже известный рецепт (steam), событие не пишется
            r = client.post("/api/discover", json={"a": "fire", "b": "water", "nick": "Н", "device_id": "d2"})
            assert r.json()["status"] == "known"
            ev = client.get("/api/events").json()
            assert ev["events"] == []


class TestChallenge:
    def test_challenge_endpoint(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            ch = client.get("/api/challenge").json()
            assert ch["ok"] is True
            assert ch["target"] in srv.CHALLENGE_TARGETS
            assert ch["target_name"]
            assert ch["hint"]
            assert ch["completions"] == 0
            assert ch["my_points"] == 0

    def test_challenge_target_deterministic(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        assert srv._challenge_target_for("2026-09-10") == srv._challenge_target_for("2026-09-10")
        assert srv._challenge_target_for("2026-01-01") in srv.CHALLENGE_TARGETS

    def test_challenge_win_flow(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeOK("Победное"))
        client = TestClient(srv.app)
        with client:
            ch = client.get("/api/challenge").json()
            target = ch["target"]
            # подобрать ДВА ингредиента, не образующих известного рецепта с целью
            conn = srv.get_db()
            others = []
            for o in ["obsidian", "smoke", "ash", "tornado", "crystal", "dust", "sky", "cloud", "rain", "snow"]:
                if o == target:
                    continue
                pk = srv.canonical_pair_key(target, o)
                if not conn.execute("SELECT 1 FROM recipes WHERE pair_key = ?", (pk,)).fetchone():
                    others.append(o)
                    if len(others) == 2:
                        break
            conn.close()
            assert len(others) == 2
            other, other2 = others

            # первый игрок выполняет цель
            r = client.post("/api/discover", json={"a": target, "b": other, "nick": "Чемпион", "device_id": "d-win"})
            assert r.json()["status"] == "created"
            assert r.json()["challenge"]["won"] is True
            assert r.json()["challenge"]["first"] is True
            assert r.json()["challenge"]["target_name"] == ch["target_name"]

            # цель НЕ закрыта: первый зафиксирован, счётчик выполнений = 1
            ch2 = client.get("/api/challenge").json()
            assert ch2["first_nick"] == "Чемпион"
            assert ch2["completions"] == 1

            # второй игрок ТОЖЕ может выполнить цель (день не заканчивается)
            r2 = client.post("/api/discover", json={"a": target, "b": other2, "nick": "Опоздал", "device_id": "d-late"})
            assert r2.json()["challenge"]["won"] is True
            assert r2.json()["challenge"]["first"] is False

            ch3 = client.get("/api/challenge").json()
            assert ch3["completions"] == 2
            assert ch3["first_nick"] == "Чемпион"

            # повторное выполнение тем же игроком награду повторно НЕ даёт
            r3 = client.post("/api/discover", json={"a": target, "b": other2, "nick": "Опоздал", "device_id": "d-late"})
            # пара уже открыта — статус known, challenge не начисляется
            assert r3.json()["status"] == "known"
            ch4 = client.get("/api/challenge", params={"device_id": "d-late"}).json()
            assert ch4["my_points"] == 1
