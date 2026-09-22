"""
Регрессии T02+T07: угон идентичности через ник и нормализация ников.

Сценарии (запускаются в T09; на машине разработки нет fastapi — не исполняются):
- второй device НЕ может присвоить занятый ник через brew-check/house/register;
- ник меняется только через POST /api/me, с проверкой занятости;
- вне правил ник -> 400 и ничего не записано (T07); a/b без slug-валидации -> 422;
- отголоски резонанса кредитуются по device_id автора, а не по нику;
- delete_account чистит авторство только своего устройства;
- миграция players.nick UNIQUE идемпотентна и переименовывает дубли.
"""

import hashlib
import os
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch, fake_llm=None):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "nick.db"))
    if fake_llm is not None:
        monkeypatch.setattr(srv, "get_llm", lambda: fake_llm)
    return srv


class FakeNamePerPair:
    """Детерминированная LLM: имя вещества уникально для пары."""

    def available(self):
        return True

    def generate(self, a, b, a_name, b_name, pair_key):
        return {"combinable": True, "name": f"Особенный {a}{b}"}


def _me(client, device_id, nick):
    r = client.post("/api/me", json={"device_id": device_id, "nick": nick})
    assert r.status_code == 200, r.text
    return r.json()


class TestNickHijack:
    def test_brew_check_does_not_rename_existing_device(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-victim", "Варда")
            _me(client, "dev-attacker", "Злодей")
            # атака: brew-check с чужим ником со стороны устройства атакующего
            r = client.post("/api/brew-check", json={
                "a": "fire", "b": "water", "nick": "Варда", "device_id": "dev-attacker",
            })
            assert r.status_code == 200
            assert client.get("/api/me", params={"device_id": "dev-attacker"}).json()["nick"] == "Злодей"
            assert client.get("/api/me", params={"device_id": "dev-victim"}).json()["nick"] == "Варда"

    def test_new_device_cannot_take_occupied_nick(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-victim", "Варда")
            r = client.post("/api/brew-check", json={
                "a": "fire", "b": "water", "nick": "Варда", "device_id": "dev-new",
            })
            assert r.status_code == 400
            # новая система не зарегистрирована (ничего не записано)
            assert client.get("/api/me", params={"device_id": "dev-new"}).json()["nick"] == ""

    def test_register_and_house_do_not_rename(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-1", "Варда")
            r = client.post("/api/house", json={
                "device_id": "dev-1", "nick": "Атака", "house": {"theme": "cobalt"},
            })
            assert r.status_code == 200
            assert r.json()["nick"] == "Варда"  # витринный ник с сервера, не из запроса
            assert client.get("/api/me", params={"device_id": "dev-1"}).json()["nick"] == "Варда"
            r2 = client.post("/api/player/register", json={
                "a": "fire", "b": "water", "nick": "Атака2", "device_id": "dev-1",
            })
            assert r2.status_code == 200
            assert r2.json()["nick"] == "Варда"

    def test_rename_only_via_api_me_with_occupancy_check(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-1", "Варда")
            _me(client, "dev-2", "Нимфа")
            # занятый ник — 400
            assert client.post("/api/me", json={"device_id": "dev-2", "nick": "Варда"}).status_code == 400
            assert client.get("/api/me", params={"device_id": "dev-2"}).json()["nick"] == "Нимфа"
            # освободившийся ник можно взять
            assert client.post("/api/me", json={"device_id": "dev-1", "nick": "Кассандра"}).status_code == 200
            assert client.post("/api/me", json={"device_id": "dev-2", "nick": "Варда"}).status_code == 200


class TestNickNormalization:
    def test_invalid_nick_on_new_device_is_400_nothing_written(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            for bad in ("X", "🔥" * 3, "a" * 30, "  Варда  "):  # последний — не clean_nick
                r = client.post("/api/brew-check", json={
                    "a": "fire", "b": "water", "nick": bad, "device_id": "dev-bad",
                })
                assert r.status_code == 400, (bad, r.text)
            assert client.get("/api/me", params={"device_id": "dev-bad"}).json()["nick"] == ""

    def test_unnormalized_nick_on_known_device_does_not_mutate(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-1", "Варда")
            r = client.post("/api/brew-check", json={
                "a": "fire", "b": "water", "nick": "Варда!", "device_id": "dev-1",
            })
            assert r.status_code == 200  # контракт online.gd не ломается
            assert client.get("/api/me", params={"device_id": "dev-1"}).json()["nick"] == "Варда"

    def test_brew_check_slug_validation_a_b(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:
            for bad in ("<img onerror=x>", "fire water!!", "a" * 65, "FIRE"):
                r = client.post("/api/brew-check", json={
                    "a": bad, "b": "water", "nick": "Варда", "device_id": "dev-1",
                })
                assert r.status_code == 422, (bad, r.text)


class TestEchoesByDevice:
    def _discover(self, client, a, b, nick, device):
        r = client.post("/api/discover", json={"a": a, "b": b, "nick": nick, "device_id": device})
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "created"
        return r.json()

    def test_credit_follows_author_device_after_rename(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeNamePerPair())
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-author", "Варда")
            _me(client, "dev-brewer", "Плавильщик")
            _me(client, "dev-hijacker", "Нейтрал")
            self._discover(client, "stone", "plant", "Варда", "dev-author")
            # автор переименовывается — старый ник освобождается
            assert client.post("/api/me", json={"device_id": "dev-author", "nick": "Кассандра"}).status_code == 200
            # хиджер занимает старый ник ЛЕГАЛЬНО (ник свободен)
            assert client.post("/api/me", json={"device_id": "dev-hijacker", "nick": "Варда"}).status_code == 200
            # чужая повторная варка -> отголосок автору по device_id, не хиджеру
            self._discover(client, "clay", "fire", "Плавильщик", "dev-brewer")  # своя пара
            r = client.post("/api/brew-check", json={
                "a": "plant", "b": "stone", "nick": "Плавильщик", "device_id": "dev-brewer",
            })
            assert r.status_code == 200
            conn = srv.get_db()
            try:
                author_echo = conn.execute(
                    "SELECT balance, total FROM echoes WHERE device_id = 'dev-author'"
                ).fetchone()
                hijacker_echo = conn.execute(
                    "SELECT balance, total FROM echoes WHERE device_id = 'dev-hijacker'"
                ).fetchone()
            finally:
                conn.close()
            assert author_echo is not None and author_echo["total"] >= 1
            assert hijacker_echo is None or hijacker_echo["total"] == 0

    def test_own_repeat_after_rename_not_credited(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeNamePerPair())
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-1", "Варда")
            self._discover(client, "stone", "plant", "Варда", "dev-1")
            client.post("/api/me", json={"device_id": "dev-1", "nick": "Кассандра"})
            # повтор СВОЕЙ пары тем же устройством — без отголоска себе
            r = client.post("/api/brew-check", json={
                "a": "stone", "b": "plant", "nick": "Кассандра", "device_id": "dev-1",
            })
            assert r.status_code == 200
            conn = srv.get_db()
            try:
                row = conn.execute("SELECT total FROM echoes WHERE device_id = 'dev-1'").fetchone()
            finally:
                conn.close()
            assert row is None or row["total"] == 0


class TestAccountLifecycle:
    def test_delete_clears_only_own_device(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeNamePerPair())
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-a", "Аврора")
            _me(client, "dev-b", "Борей")
            da = self._created(client, "stone", "plant", "Аврора", "dev-a")
            db = self._created(client, "clay", "fire", "Борей", "dev-b")
            r = client.request("DELETE", "/api/account", params={"device_id": "dev-a"})
            assert r.status_code == 200
            conn = srv.get_db()
            try:
                a_row = conn.execute("SELECT author, author_device FROM elements WHERE slug = ?", (da,)).fetchone()
                b_row = conn.execute("SELECT author, author_device FROM elements WHERE slug = ?", (db,)).fetchone()
            finally:
                conn.close()
            assert a_row["author"] is None and a_row["author_device"] is None
            assert b_row["author"] == "Борей" and b_row["author_device"] == "dev-b"

    @staticmethod
    def _created(client, a, b, nick, device):
        body = client.post("/api/discover", json={"a": a, "b": b, "nick": nick, "device_id": device}).json()
        assert body["status"] == "created"
        return body["discovery"]["slug"]

    def test_export_still_works(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, FakeNamePerPair())
        client = TestClient(srv.app)
        with client:
            _me(client, "dev-a", "Аврора")
            slug = self._created(client, "stone", "plant", "Аврора", "dev-a")
            data = client.get("/api/account/export", params={"device_id": "dev-a"}).json()
            assert data["found"] is True
            assert [d["slug"] for d in data["data"]["discoveries"]] == [slug]
            # после переименования экспорт не теряется (ключ — device_id)
            client.post("/api/me", json={"device_id": "dev-a", "nick": "Кассандра"})
            data2 = client.get("/api/account/export", params={"device_id": "dev-a"}).json()
            assert [d["slug"] for d in data2["data"]["discoveries"]] == [slug]


class TestNickUniqueMigration:
    def test_idempotent_and_resolves_collisions(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = TestClient(srv.app)
        with client:  # init_db уже прошёл (idx_players_nick UNIQUE)
            conn = srv.get_db()
            try:
                # симулируем старую БД: убираем уникальный индекс и сажаем дубли
                conn.execute("DROP INDEX idx_players_nick")
                conn.execute("INSERT INTO players (nick, device_id) VALUES ('Двойник','old-1')")
                conn.execute("INSERT INTO players (nick, device_id) VALUES ('Двойник','old-2')")
                conn.execute("INSERT INTO players (nick, device_id) VALUES ('Двойник','bot-9')")
                conn.commit()
                srv._migrate_nick_identity(conn)
                srv._migrate_nick_identity(conn)  # идемпотентность
                conn.commit()
                nicks = [
                    r["nick"] for r in conn.execute(
                        "SELECT nick FROM players WHERE device_id IN ('old-1','old-2','bot-9') ORDER BY device_id"
                    )
                ]
                assert len(set(nicks)) == 3
                assert "Двойник" in nicks  # оригинальный владелец (минимальный id) сохраняет ник
                suf = hashlib.sha256(b"old-2").hexdigest()[:4]
                assert any(suf in n for n in nicks)  # детерминированный суффикс по device
                idx = {r["name"]: r["unique"] for r in conn.execute("PRAGMA index_list(players)")}
                assert idx["idx_players_nick"] == 1
            finally:
                conn.close()
