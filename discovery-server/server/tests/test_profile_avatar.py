"""
Тесты профиля игрока и процедурных аватаров.

- аватар детерминирован (один ник -> один аватар, разные ники -> обычно разный);
- ник нормализуется (trim, схлопывание пробелов, спецсимволы отбрасываются);
- GET/POST /api/me — чтение и установка ника, аватар из ника;
- аватары присутствуют в ленте, зале славы, списке мира и цели-гонке.
"""

import os
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch, fake_llm=None):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "profile.db"))
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


class TestAvatar:
    def test_avatar_deterministic(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        a1 = srv.avatar_for("Варда")
        a2 = srv.avatar_for("Варда")
        assert a1 == a2
        assert set(a1.keys()) == {"bg", "accent", "sym", "ring"}
        assert a1["bg"].startswith("#") and len(a1["bg"]) == 7
        assert a1["bg"] != a1["accent"]  # фон и акцент не совпадают
        assert 0 <= a1["sym"] < 12
        assert isinstance(a1["ring"], bool)
        # разные сиды чаще всего дают разные аватары
        b = srv.avatar_for("Гелиос")
        assert a1 != b

    def test_clean_nick(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        assert srv.clean_nick("  Варда  ") == "Варда"
        assert srv.clean_nick("  Вар   да  ") == "Вар да"
        assert srv.clean_nick("Варда!!!123") == "Варда123"
        assert srv.clean_nick("") == ""
        assert srv.clean_nick("Х") == ""            # короче 2 символов
        assert srv.clean_nick("А" * 30) == ""       # длиннее 24


class TestProfile:
    def test_get_empty_profile(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            r = client.get("/api/me", params={"device_id": "dev-new"})
            assert r.status_code == 200
            body = r.json()
            assert body["ok"] is True and body["nick"] == ""
            assert body["avatar"]["bg"].startswith("#")

    def test_set_and_get_profile(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            r = client.post("/api/me", json={"device_id": "dev-1", "nick": "  Варда  "})
            assert r.status_code == 200
            body = r.json()
            assert body["nick"] == "Варда"
            assert body["avatar"]["bg"].startswith("#")
            # повторное чтение возвращает сохранённый ник
            r2 = client.get("/api/me", params={"device_id": "dev-1"}).json()
            assert r2["nick"] == "Варда"
            assert r2["avatar"] == body["avatar"]

    def test_set_invalid_nick_rejected(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            assert client.post("/api/me", json={"device_id": "d", "nick": "Х"}).status_code == 400
            assert client.post("/api/me", json={"device_id": "d", "nick": ""}).status_code == 400

    def test_rename_keeps_device(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            client.post("/api/me", json={"device_id": "dev-1", "nick": "Варда"})
            r = client.post("/api/me", json={"device_id": "dev-1", "nick": "Нимфа"}).json()
            assert r["nick"] == "Нимфа"
            r2 = client.get("/api/me", params={"device_id": "dev-1"}).json()
            assert r2["nick"] == "Нимфа"


class TestAvatarsInResponses:
    def test_avatars_everywhere(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeOK())
        client = TestClient(srv.app)
        with client:
            # создаём первооткрытие от именованного игрока
            r = client.post("/api/discover", json={"a": "dust", "b": "sky", "nick": "Варда", "device_id": "d1"})
            body = r.json()
            assert body["status"] == "created"
            assert body["discovery"]["avatar"]["bg"].startswith("#")

            ev = client.get("/api/events").json()["events"]
            assert ev[0]["avatar"]["bg"].startswith("#")

            hall = client.get("/api/hall-of-fame").json()["hall"]
            assert any(h["nick"] == "Варда" and h["avatar"]["bg"].startswith("#") for h in hall)

            world = client.get("/api/world", params={"per_page": 100}).json()["elements"]
            authored = [e for e in world if e.get("author") == "Варда"]
            assert authored and authored[0]["avatar"]["bg"].startswith("#")
            # базовые вещества без автора — без аватара
            base = [e for e in world if e["slug"] == "fire"]
            assert base and base[0]["avatar"] is None
