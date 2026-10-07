"""
Социальные интеракции S1: друзья, почтовый ящик, блок, весточки Светика.

Идиома — та же, что в tests/test_house_visits.py (19 из 24 модулей сервера):
in-process TestClient(srv.app) + подмена DB_PATH + явный init_db(). Фикстура
process_server здесь не годится: подпроцесс не даёт подменить ни _now_dt
(уборка почты, триггер «return»), ни get_llm (весточки).
"""

import os
import sys

import pytest
from fastapi.testclient import TestClient

SERVER_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

SOCIAL_TABLES = ("friend_edges", "messages", "blocks", "spirit_messages", "social_state")


def _srv(tmp_path, monkeypatch, llm=None):
    sys.path.insert(0, SERVER_DIR)
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "social.db"))
    if llm is not None:
        monkeypatch.setattr(srv, "get_llm", lambda: llm)
    return srv


def _client(srv):
    srv.init_db()
    return TestClient(srv.app)


def _player(client, nick, device_id):
    """Регистрация: строка в players появляется только через POST /api/me."""
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


class TestSchema:
    def test_fresh_db_has_social_tables(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            have = _tables(conn)
        finally:
            conn.close()
        for t in SOCIAL_TABLES:
            assert t in have, (t, sorted(have))

    def test_migration_file_alone_creates_same_shape(self, tmp_path, monkeypatch):
        """Свежая БД (init_db) и существующая (только 001_social.sql) совпадают.

        Оба пути объявления таблиц — приём vein_points/sigil_*: DDL продублирован
        в schema.sql и в миграции. Без этого теста копии разъезжаются молча.
        """
        import sqlite3

        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            reference = {t: _columns(conn, t) for t in SOCIAL_TABLES}
        finally:
            conn.close()

        mig_path = os.path.join(SERVER_DIR, "migrations", "001_social.sql")
        assert os.path.exists(mig_path), mig_path
        with open(mig_path, "r", encoding="utf-8") as f:
            ddl = f.read()
        bare = sqlite3.connect(str(tmp_path / "bare.db"))
        bare.row_factory = sqlite3.Row
        bare.executescript(ddl)
        try:
            for t in SOCIAL_TABLES:
                assert _columns(bare, t) == reference[t], t
        finally:
            bare.close()

    def test_pair_key_is_primary_key_of_friend_edges(self, tmp_path, monkeypatch):
        """Одна строка на пару — на уровне БД, а не проверками в коде."""
        srv = _srv(tmp_path, monkeypatch)
        srv.init_db()
        conn = srv.get_db()
        try:
            pk = [c[0] for c in _columns(conn, "friend_edges") if c[3]]
        finally:
            conn.close()
        assert pk == ["pair_key"], pk

    def test_constants_are_server_side(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        assert srv.FRIEND_MAX == 50
        assert srv.FRIEND_PENDING_OUT_MAX == 20
        assert srv.MSG_MAX_LEN == 500
        assert srv.MSG_PER_DAY == 50
        assert srv.MSG_RETENTION_DAYS == 30
        assert srv.MSG_KEEP_PER_PAIR == 200
        assert srv.MSG_PREVIEW_LEN == 60
        assert srv.SPIRIT_DEVICE == "npc-spirit"
        assert srv.SPIRIT_NICK == "Светик"
        assert srv.SPIRIT_LLM_TIMEOUT == 8
        assert srv.SPIRIT_RETURN_DAYS == 3
        assert srv.SPIRIT_LLM_PER_DAY_GLOBAL == 200
        assert srv.SPIRIT_BODY_MAX == 200
        # зарезервированный device_id не должен наследовать семантику seed-ботов
        assert not srv.SPIRIT_DEVICE.startswith("bot-")


class TestFriendRequest:
    def test_request_creates_pending_edge(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["ok"] is True and body["state"] == "pending"
        assert body["peer"]["device_id"] == "dev-b" and body["peer"]["nick"] == "Мира"
        assert body["peer"]["avatar"], body["peer"]

    def test_repeat_is_idempotent_and_does_not_duplicate(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        for _ in range(2):
            r = client.post("/api/friend/request",
                            json={"device_id": "dev-a", "target_nick": "Мира"})
            assert r.status_code == 200, r.text
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM friend_edges").fetchone()["c"]
        finally:
            conn.close()
        assert n == 1, "pair_key в PRIMARY KEY делает вторую заявку невозможной"

    def test_counter_request_accepts(self, tmp_path, monkeypatch):
        """Встречная заявка принимается: игрок не видит «заявку в ответ на заявку»."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        r = client.post("/api/friend/request", json={"device_id": "dev-b", "target_nick": "Варда"})
        assert r.status_code == 200, r.text
        assert r.json()["state"] == "accepted", r.json()
        conn = srv.get_db()
        try:
            row = conn.execute("SELECT state, requester_device FROM friend_edges").fetchone()
            n = conn.execute("SELECT COUNT(*) AS c FROM friend_edges").fetchone()["c"]
        finally:
            conn.close()
        assert n == 1 and row["state"] == "accepted"
        assert row["requester_device"] == "dev-a", "первый заявитель сохраняется"

    def test_unknown_nick_self_and_bot(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-a", "target_nick": "НетТакой"})
        assert r.status_code == 400 and r.json()["detail"] == "target_not_found", r.text
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-a", "target_nick": "Варда"})
        assert r.status_code == 400 and r.json()["detail"] == "self", r.text
        # seed-боты (Issue #17) живут в players с device_id LIKE 'bot-%'.
        # id вне диапазона сида (bot-0..bot-3), приём test_nick_hijack.py.
        conn = srv.get_db()
        try:
            conn.execute(
                "INSERT INTO players (nick, device_id, created_at, last_seen) "
                "VALUES ('Бот', 'bot-9', ?, ?)", (srv._today(), srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-a", "target_nick": "Бот"})
        assert r.status_code == 400 and r.json()["detail"] == "bot", r.text

    def test_already_friends_conflict(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a", "accept": True})
        r = client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r.status_code == 409 and r.json()["detail"] == "already_friends", r.text

    def test_pending_out_limit(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "FRIEND_PENDING_OUT_MAX", 3)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        for i in range(3):
            _player(client, "Сосед%d" % i, "dev-p%d" % i)
            r = client.post("/api/friend/request",
                            json={"device_id": "dev-a", "target_nick": "Сосед%d" % i})
            assert r.status_code == 200, (i, r.text)
        _player(client, "Четвёртый", "dev-p3")
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-a", "target_nick": "Четвёртый"})
        assert r.status_code == 429 and r.json()["detail"] == "pending_limit", r.text

    def test_friend_limit(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "FRIEND_MAX", 1)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _player(client, "Третья", "dev-c")
        client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a", "accept": True})
        r = client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Третья"})
        assert r.status_code == 429 and r.json()["detail"] == "friend_limit", r.text

    def test_spirit_edge_does_not_take_friend_slot(self, tmp_path, monkeypatch):
        """Ребро Светика закреплено и не учитывается в FRIEND_MAX (задача 8)."""
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "FRIEND_MAX", 1)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        conn = srv.get_db()
        try:
            conn.execute(
                "INSERT INTO friend_edges (pair_key, a_device, b_device, state, "
                "requester_device, created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
                (srv.canonical_pair_key("dev-a", srv.SPIRIT_DEVICE), "dev-a",
                 srv.SPIRIT_DEVICE, "accepted", srv.SPIRIT_DEVICE,
                 srv._now_iso(), srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        _player(client, "Мира", "dev-b")
        r = client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r.status_code == 200, r.text

    def test_counter_request_respects_friend_limit(self, tmp_path, monkeypatch):
        """Встречная заявка не обходит FRIEND_MAX (приём гейтит и задача 4)."""
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "FRIEND_MAX", 1)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _player(client, "Третья", "dev-c")
        conn = srv.get_db()
        try:
            # один принятый друг — слот уже занят
            conn.execute(
                "INSERT INTO friend_edges (pair_key, a_device, b_device, state, "
                "requester_device, created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
                (srv.canonical_pair_key("dev-a", "dev-b"), "dev-a", "dev-b",
                 "accepted", "dev-a", srv._now_iso(), srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        # входящая заявка от Третьей
        r = client.post("/api/friend/request", json={"device_id": "dev-c", "target_nick": "Варда"})
        assert r.status_code == 200, r.text
        # ответ своей заявкой — тот же приём, лимит обязан сработать
        r = client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Третья"})
        assert r.status_code == 429 and r.json()["detail"] == "friend_limit", r.text
        conn = srv.get_db()
        try:
            row = conn.execute(
                "SELECT state FROM friend_edges WHERE pair_key = ?",
                (srv.canonical_pair_key("dev-a", "dev-c"),)).fetchone()
        finally:
            conn.close()
        assert row["state"] == "pending", row["state"]


def _ask(client, target_nick, device_id="dev-a"):
    r = client.post("/api/friend/request",
                    json={"device_id": device_id, "target_nick": target_nick})
    assert r.status_code == 200, r.text
    return r.json()


class TestFriendRespond:
    @pytest.mark.skip(reason="inbox появляется в задаче 7")
    def test_accept_makes_friendship_symmetric(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-b", "requester_device": "dev-a",
                              "accept": True})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["ok"] is True and body["accepted"] is True
        assert body["peer"]["device_id"] == "dev-a" and body["peer"]["nick"] == "Варда"
        # список один на пару: отдельного «принять от имени второго» не нужно
        inbox_a = client.get("/api/social/inbox", params={"device_id": "dev-a"})
        inbox_b = client.get("/api/social/inbox", params={"device_id": "dev-b"})
        assert inbox_a.status_code == 200 and inbox_b.status_code == 200, \
            (inbox_a.text, inbox_b.text)

    def test_decline_deletes_edge_and_allows_new_request(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-b", "requester_device": "dev-a",
                              "accept": False})
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is False
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM friend_edges").fetchone()["c"]
        finally:
            conn.close()
        assert n == 0, "отказ хранится удалением: история отказов не нужна"
        # повторная заявка после отказа допустима
        r2 = client.post("/api/friend/request",
                         json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r2.status_code == 200 and r2.json()["state"] == "pending", r2.text

    def test_second_respond_is_not_found(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a",
                          "accept": True})
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-b", "requester_device": "dev-a",
                              "accept": True})
        assert r.status_code == 404 and r.json()["detail"] == "request_not_found", r.text
        # ребро осталось принятым: повторный respond его не портит
        conn = srv.get_db()
        try:
            state = conn.execute("SELECT state FROM friend_edges").fetchone()["state"]
        finally:
            conn.close()
        assert state == "accepted", state

    def test_unknown_requester_is_not_found(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-b", "requester_device": "dev-нет",
                              "accept": True})
        assert r.status_code == 404 and r.json()["detail"] == "request_not_found", r.text

    def test_third_party_cannot_accept(self, tmp_path, monkeypatch):
        """Принять может только адресат: (a_device=? OR b_device=?) в WHERE."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _player(client, "Третья", "dev-c")
        _ask(client, "Мира")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-c", "requester_device": "dev-a",
                              "accept": True})
        assert r.status_code == 404 and r.json()["detail"] == "request_not_found", r.text
        conn = srv.get_db()
        try:
            state = conn.execute("SELECT state FROM friend_edges").fetchone()["state"]
        finally:
            conn.close()
        assert state == "pending", state

    def test_self_respond_rejected(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-a", "requester_device": "dev-a",
                              "accept": True})
        assert r.status_code == 400 and r.json()["detail"] == "self", r.text

    def test_accept_respects_own_friend_limit(self, tmp_path, monkeypatch):
        """Лимит проверяется у ПРИНИМАЮЩЕГО, а не только у инициатора."""
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "FRIEND_MAX", 1)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _player(client, "Третья", "dev-c")
        # заявители — Мира и Третья, адресат один: Варда (dev-a) принимает
        _ask(client, "Варда", device_id="dev-b")  # Варда получила заявку
        _ask(client, "Варда", device_id="dev-c")  # и ещё одну
        r1 = client.post("/api/friend/respond",
                         json={"device_id": "dev-a", "requester_device": "dev-b",
                               "accept": True})
        assert r1.status_code == 200, r1.text
        r2 = client.post("/api/friend/respond",
                         json={"device_id": "dev-a", "requester_device": "dev-c",
                               "accept": True})
        assert r2.status_code == 429 and r2.json()["detail"] == "friend_limit", r2.text

    @pytest.mark.skip(reason="block появляется в задаче 5")
    def test_block_prevents_accept(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        client.post("/api/friend/block",
                    json={"device_id": "dev-b", "target_device": "dev-a"})
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-b", "requester_device": "dev-a",
                              "accept": True})
        assert r.status_code == 403 and r.json()["detail"] == "blocked", r.text
