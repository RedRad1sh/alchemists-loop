"""
Социальные интеракции S1: друзья, почтовый ящик, блок, весточки Светика.

Идиома — та же, что в tests/test_house_visits.py (19 из 24 модулей сервера):
in-process TestClient(srv.app) + подмена DB_PATH + явный init_db(). Фикстура
process_server здесь не годится: подпроцесс не даёт подменить ни _now_dt
(уборка почты, триггер «return»), ни get_llm (весточки).
"""

import datetime as _dt
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
        """Принять может только адресат: у третьего игрока другой pair_key, и 404
        даёт уже фильтр по pair_key. `(a_device=? OR b_device=?)` в WHERE — пояс
        на подтяжках: тест, где отказ держится только на нём, против этой схемы
        не строится."""
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

    def test_requester_cannot_accept_own_request(self, tmp_path, monkeypatch):
        """Заявитель не принимает свою же заявку: отказ держит `requester_device=?`
        в WHERE. Без него заявитель стал бы другом в одностороннем порядке."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        r = client.post("/api/friend/respond",
                        json={"device_id": "dev-a", "requester_device": "dev-b",
                              "accept": True})
        assert r.status_code == 404 and r.json()["detail"] == "request_not_found", r.text
        conn = srv.get_db()
        try:
            state = conn.execute("SELECT state FROM friend_edges").fetchone()["state"]
        finally:
            conn.close()
        assert state == "pending", state

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


def _seed_message(srv, pair, from_device, body):
    """Прямая вставка в messages: до задачи 6 роута отправки ещё нет."""
    conn = srv.get_db()
    try:
        conn.execute(
            "INSERT INTO messages (pair_key, from_device, body, sent_at) "
            "VALUES (?,?,?,?)",
            (srv.canonical_pair_key(*pair), from_device, body, srv._now_iso()))
        conn.commit()
    finally:
        conn.close()


def _messages(srv, pair):
    conn = srv.get_db()
    try:
        rows = conn.execute(
            "SELECT body FROM messages WHERE pair_key = ? ORDER BY id",
            (srv.canonical_pair_key(*pair),)).fetchall()
    finally:
        conn.close()
    return [r["body"] for r in rows]


class TestRemoveAndBlock:
    def test_remove_clears_thread_for_both(self, tmp_path, monkeypatch):
        """«Удалил друга, а переписка осталась у него» — дыра в приватности."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a",
                          "accept": True})
        _seed_message(srv, ("dev-a", "dev-b"), "dev-a", "привет")
        _seed_message(srv, ("dev-a", "dev-b"), "dev-b", "здорово")
        r = client.post("/api/friend/remove",
                        json={"device_id": "dev-a", "peer_device": "dev-b"})
        assert r.status_code == 200 and r.json()["ok"] is True, r.text
        assert _messages(srv, ("dev-a", "dev-b")) == []
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM friend_edges").fetchone()["c"]
        finally:
            conn.close()
        assert n == 0

    def test_remove_without_edge_is_not_found(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        r = client.post("/api/friend/remove",
                        json={"device_id": "dev-a", "peer_device": "dev-b"})
        assert r.status_code == 404 and r.json()["detail"] == "not_friends", r.text

    def test_remove_leaves_pending_request_alone(self, tmp_path, monkeypatch):
        """remove гейтится по accepted, а не по любому ребру: pending-заявка
        остаётся в БД нетронутой (отклоняет её адресат через respond, а не
        заявитель через remove)."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        r = client.post("/api/friend/remove",
                        json={"device_id": "dev-a", "peer_device": "dev-b"})
        assert r.status_code == 404 and r.json()["detail"] == "not_friends", r.text
        conn = srv.get_db()
        try:
            row = conn.execute("SELECT state FROM friend_edges").fetchone()
        finally:
            conn.close()
        assert row is not None and row["state"] == "pending", row

    def test_block_hides_thread_and_blocks_requests(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a",
                          "accept": True})
        _seed_message(srv, ("dev-a", "dev-b"), "dev-b", "напиши мне")
        r = client.post("/api/friend/block",
                        json={"device_id": "dev-a", "target_device": "dev-b"})
        assert r.status_code == 200 and r.json()["ok"] is True, r.text
        assert _messages(srv, ("dev-a", "dev-b")) == []
        # блок мешает заявке в обе стороны, ответ не раскрывает кто заблокировал
        r1 = client.post("/api/friend/request",
                         json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r1.status_code == 403 and r1.json()["detail"] == "blocked", r1.text
        r2 = client.post("/api/friend/request",
                         json={"device_id": "dev-b", "target_nick": "Варда"})
        assert r2.status_code == 403 and r2.json()["detail"] == "blocked", r2.text

    def test_block_without_edge_still_works(self, tmp_path, monkeypatch):
        """Блок — защита от навязчивых, ребра может и не быть."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        r = client.post("/api/friend/block",
                        json={"device_id": "dev-a", "target_device": "dev-b"})
        assert r.status_code == 200, r.text
        r = client.post("/api/friend/request",
                        json={"device_id": "dev-b", "target_nick": "Варда"})
        assert r.status_code == 403 and r.json()["detail"] == "blocked", r.text

    def test_unblock_returns_nothing_but_allows_request(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a",
                          "accept": True})
        _seed_message(srv, ("dev-a", "dev-b"), "dev-b", "до связи")
        client.post("/api/friend/block",
                    json={"device_id": "dev-a", "target_device": "dev-b"})
        r = client.post("/api/friend/unblock",
                        json={"device_id": "dev-a", "target_device": "dev-b"})
        assert r.status_code == 200 and r.json()["ok"] is True, r.text
        assert _messages(srv, ("dev-a", "dev-b")) == [], \
            "разблокировка не возвращает переписку — это осознанное действие"
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM friend_edges").fetchone()["c"]
        finally:
            conn.close()
        assert n == 0, "разблокировка не возвращает ребро"
        r2 = client.post("/api/friend/request",
                         json={"device_id": "dev-a", "target_nick": "Мира"})
        assert r2.status_code == 200 and r2.json()["state"] == "pending", r2.text

    def test_spirit_cannot_be_removed_or_blocked(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        r = client.post("/api/friend/remove",
                        json={"device_id": "dev-a", "peer_device": "npc-spirit"})
        assert r.status_code == 400 and r.json()["detail"] == "npc", r.text
        r = client.post("/api/friend/block",
                        json={"device_id": "dev-a", "target_device": "npc-spirit"})
        assert r.status_code == 400 and r.json()["detail"] == "npc", r.text

    def test_block_self_rejected(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        r = client.post("/api/friend/block",
                        json={"device_id": "dev-a", "target_device": "dev-a"})
        assert r.status_code == 400 and r.json()["detail"] == "self", r.text

    def test_calling_as_the_spirit_is_rejected(self, tmp_path, monkeypatch):
        """device_id ничем не аутентифицирован, поэтому и вторая сторона пары
        проверяется: вызов от имени npc-spirit удалил бы чужое закреплённое
        ребро и вставил бы блок, который жертва сама не снимет (unblock
        удаляет только (me, target))."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Мира", "dev-b")
        r = client.post("/api/friend/remove",
                        json={"device_id": "npc-spirit", "peer_device": "dev-b"})
        assert r.status_code == 400 and r.json()["detail"] == "npc", r.text
        r = client.post("/api/friend/block",
                        json={"device_id": "npc-spirit", "target_device": "dev-b"})
        assert r.status_code == 400 and r.json()["detail"] == "npc", r.text
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM blocks").fetchone()["c"]
        finally:
            conn.close()
        assert n == 0, "отказ не должен оставлять строку в blocks"

    def test_block_twice_is_idempotent_and_unblock_of_nothing_is_ok(
            self, tmp_path, monkeypatch):
        """INSERT OR IGNORE + PK(blocks) — второй блок не даёт 500; unblock
        без строки идемпотентен, клиент не обязан различать."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        body = {"device_id": "dev-a", "target_device": "dev-b"}
        assert client.post("/api/friend/block", json=body).status_code == 200
        r = client.post("/api/friend/block", json=body)
        assert r.status_code == 200, r.text
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM blocks").fetchone()["c"]
        finally:
            conn.close()
        assert n == 1, "повтор не удваивает строку"
        r = client.post("/api/friend/unblock",
                        json={"device_id": "dev-b", "target_device": "dev-a"})
        assert r.status_code == 200 and r.json()["ok"] is True, r.text

    def test_payload_bounds(self, tmp_path, monkeypatch):
        """Пустой или гигантский идентификатор не должен доходить до БД: оба
        поля пишутся в PRIMARY KEY (blocks, friend_edges.pair_key)."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        long_id = "x" * 200
        for route, key in (("/api/friend/remove", "peer_device"),
                           ("/api/friend/block", "target_device"),
                           ("/api/friend/unblock", "target_device")):
            empty = client.post(route, json={"device_id": "", key: "dev-b"})
            assert empty.status_code == 422, (route, empty.text)
            huge = client.post(route, json={"device_id": long_id, key: "dev-b"})
            assert huge.status_code == 422, (route, huge.text)
            huge_peer = client.post(route, json={"device_id": "dev-a", key: long_id})
            assert huge_peer.status_code == 422, (route, huge_peer.text)


def _befriend(srv, client, nick_a="Варда", dev_a="dev-a", nick_b="Мира", dev_b="dev-b"):
    _player(client, nick_a, dev_a)
    _player(client, nick_b, dev_b)
    client.post("/api/friend/request", json={"device_id": dev_a, "target_nick": nick_b})
    r = client.post("/api/friend/respond",
                    json={"device_id": dev_b, "requester_device": dev_a, "accept": True})
    assert r.status_code == 200, r.text
    return dev_a, dev_b


class TestMessages:
    def test_thread_order_and_from_me(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "привет"})
        assert r.status_code == 200 and r.json()["ok"] is True, r.text
        first_id = r.json()["id"]
        client.post("/api/message/send",
                    json={"device_id": b, "peer_device": a, "body": "здорово"})
        r = client.get("/api/messages",
                       params={"device_id": a, "peer_device": b})
        assert r.status_code == 200, r.text
        rows = r.json()["messages"]
        assert [(m["body"], m["from_me"]) for m in rows] == \
            [("привет", True), ("здорово", False)], rows
        assert rows[0]["id"] == first_id

    def test_reading_marks_only_peer_messages(self, tmp_path, monkeypatch):
        """read_at — побочный эффект открытия ленты, отдельного «mark read» нет.

        Свои сообщения вставляются уже прочитанными, поэтому UPDATE обязан
        фильтровать from_device != me: иначе unread собеседника гаснет от того,
        что я сам открыл ленту.
        """
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        client.post("/api/message/send", json={"device_id": a, "peer_device": b, "body": "моё"})
        client.post("/api/message/send", json={"device_id": b, "peer_device": a, "body": "чужое"})
        client.get("/api/messages", params={"device_id": a, "peer_device": b})
        conn = srv.get_db()
        try:
            rows = conn.execute(
                "SELECT body, from_device, read_at FROM messages ORDER BY id").fetchall()
        finally:
            conn.close()
        mine = next(r for r in rows if r["body"] == "моё")
        theirs = next(r for r in rows if r["body"] == "чужое")
        assert theirs["read_at"] is not None, rows
        assert mine["read_at"] is not None, "своё пишется прочитанным при вставке"
        # Все строки, созданные /api/message/send, вставлены уже прочитанными,
        # поэтому хвост теста сеет read_at IS NULL напрямую (так живёт только
        # письмо Светика, §6.4): иначе проверка «открытие ленты читает чужое и
        # не трогает своё» краснеть не умеет.
        conn = srv.get_db()
        try:
            conn.execute("INSERT INTO messages (pair_key, from_device, body, sent_at) "
                         "VALUES (?,?,?,?)",
                         (srv.canonical_pair_key(a, b), b, "чужое непрочитано", srv._now_iso()))
            conn.execute("INSERT INTO messages (pair_key, from_device, body, sent_at) "
                         "VALUES (?,?,?,?)",
                         (srv.canonical_pair_key(a, b), a, "моё непрочитано", srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        client.get("/api/messages", params={"device_id": a, "peer_device": b})
        conn = srv.get_db()
        try:
            states = {r["body"]: r["read_at"] for r in conn.execute(
                "SELECT body, read_at FROM messages WHERE read_at IS NULL OR "
                "body IN ('чужое непрочитано', 'моё непрочитано')").fetchall()}
        finally:
            conn.close()
        assert states["чужое непрочитано"] is not None, \
            "открытие ленты выставляет read_at чужим сообщениям пары"
        assert states["моё непрочитано"] is None, \
            "фильтр from_device != me обязателен: иначе unread гаснет от моего же открытия"

    def test_since_id_returns_only_newer(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        ids = []
        for i in range(3):
            ids.append(client.post(
                "/api/message/send",
                json={"device_id": a, "peer_device": b, "body": "m%d" % i}).json()["id"])
        r = client.get("/api/messages",
                       params={"device_id": a, "peer_device": b, "since_id": ids[1]})
        assert [m["id"] for m in r.json()["messages"]] == [ids[2]], r.json()

    def test_limit_is_bounded(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        for i in range(5):
            client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "m%d" % i})
        r = client.get("/api/messages",
                       params={"device_id": a, "peer_device": b, "limit": 2})
        assert len(r.json()["messages"]) == 2, r.json()
        r = client.get("/api/messages",
                       params={"device_id": a, "peer_device": b, "limit": 100})
        assert r.status_code == 200 and len(r.json()["messages"]) == 5, r.text
        # limit зажат Query(ge=1, le=100): выход за диапазон — 422 валидации
        r = client.get("/api/messages",
                       params={"device_id": a, "peer_device": b, "limit": 5000})
        assert r.status_code == 422, r.text

    def test_strangers_and_missing_peer(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        r = client.get("/api/messages", params={"device_id": "dev-a", "peer_device": "dev-b"})
        assert r.status_code == 404 and r.json()["detail"] == "not_friends", r.text
        r = client.get("/api/messages", params={"device_id": "dev-a", "peer_device": ""})
        assert r.status_code == 400 and r.json()["detail"] == "missing_peer", r.text
        r = client.post("/api/message/send",
                        json={"device_id": "dev-a", "peer_device": "dev-b", "body": "эй"})
        assert r.status_code == 404 and r.json()["detail"] == "not_friends", r.text

    def test_other_pair_thread_is_not_readable(self, tmp_path, monkeypatch):
        """peer_device обязателен: «все переписки скопом» не отдаём."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        c, d = _befriend(srv, client, nick_a="Третья", dev_a="dev-c",
                         nick_b="Четвёртая", dev_b="dev-d")
        client.post("/api/message/send", json={"device_id": c, "peer_device": d, "body": "чужое"})
        r = client.get("/api/messages", params={"device_id": a, "peer_device": b})
        assert [m["body"] for m in r.json()["messages"]] == [], r.json()

    def test_body_validation(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        r = client.post("/api/message/send", json={"device_id": a, "peer_device": b, "body": "   "})
        assert r.status_code == 400 and r.json()["detail"] == "empty", r.text
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "ы" * (srv.MSG_MAX_LEN + 1)})
        assert r.status_code == 400 and r.json()["detail"] == "too_long", r.text
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "ы" * srv.MSG_MAX_LEN})
        assert r.status_code == 200, r.text

    def test_control_chars_and_newlines_are_cleaned(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b,
                              "body": "при\r\nвет\u0000мир\u001b[31m"})
        assert r.status_code == 200, r.text
        rows = client.get("/api/messages",
                          params={"device_id": b, "peer_device": a}).json()["messages"]
        assert rows[0]["body"] == "при\nветмир[31m", rows[0]

    def test_daily_limit_resets_next_day(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "MSG_PER_DAY", 3)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        a, b = _befriend(srv, client)
        for i in range(3):
            r = client.post("/api/message/send",
                            json={"device_id": a, "peer_device": b, "body": "m%d" % i})
            assert r.status_code == 200, (i, r.text)
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "m3"})
        assert r.status_code == 429 and r.json()["detail"] == "daily_limit", r.text
        # лимит на ОТПРАВКУ: получать можно и дальше
        r = client.post("/api/message/send",
                        json={"device_id": b, "peer_device": a, "body": "ответ"})
        assert r.status_code == 200, r.text
        clock["now"] = _dt.datetime(2026, 10, 8, 0, 30)
        r = client.post("/api/message/send",
                        json={"device_id": a, "peer_device": b, "body": "утро"})
        assert r.status_code == 200, r.text

    def test_spirit_does_not_answer(self, tmp_path, monkeypatch):
        """Светик не читает ответы: отправка на npc-spirit запрещена."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        r = client.post("/api/message/send",
                        json={"device_id": "dev-a", "peer_device": "npc-spirit",
                              "body": "привет"})
        assert r.status_code == 403 and r.json()["detail"] == "npc", r.text

    def test_blocked_pair_cannot_read_or_write(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        client.post("/api/friend/block", json={"device_id": a, "target_device": b})
        # блок удалил ребро, поэтому дальше 404; проверяем, что не 200
        r = client.get("/api/messages", params={"device_id": b, "peer_device": a})
        assert r.status_code in (403, 404), r.text
        r = client.post("/api/message/send",
                        json={"device_id": b, "peer_device": a, "body": "эй"})
        assert r.status_code in (403, 404), r.text
