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
        # Симметрия — не статус, а содержимое: друг виден с обеих сторон. Без
        # этих двух строк тест зелё и на пустых списках (замечание ревьюера).
        assert [f["device_id"] for f in _humans(inbox_a.json())] == ["dev-b"], \
            inbox_a.json()["friends"]
        assert [f["device_id"] for f in _humans(inbox_b.json())] == ["dev-a"], \
            inbox_b.json()["friends"]
        assert inbox_a.json()["requests_total"] == 0 and inbox_b.json()["requests_total"] == 0, \
            "принятая заявка не оставляется висеть входящей"

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
    """Прямая вставка в messages: нужна, где лента важна до отправки или с
    особым sent_at. Обычные сообщения пишем через _send."""
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

        read_at значит «прочитано ПОЛУЧАТЕЛЕМ» и при вставке остаётся NULL,
        поэтому UPDATE обязан фильтровать from_device != me: без него моё же
        открытие ленты выставило бы read_at на ИСХОДЯЩИЕ строки и погасило бы
        бейдж собеседника. Краснеет на удалении этого фильтра.
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
        assert theirs["read_at"] is not None, \
            "открытие ленты выставляет read_at чужим сообщениям пары"
        assert mine["read_at"] is None, \
            "исходящие — не мои на прочтение: их читает получатель"

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


def _send(client, dev, peer, body):
    r = client.post("/api/message/send",
                    json={"device_id": dev, "peer_device": peer, "body": body})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _inbox(client, device_id):
    r = client.get("/api/social/inbox", params={"device_id": device_id})
    assert r.status_code == 200, r.text
    return r.json()


def _count(srv, sql, args=()):
    conn = srv.get_db()
    try:
        return conn.execute(sql, args).fetchone()["c"]
    finally:
        conn.close()


def _humans(body):
    """Живые друзья без Светика: его строка добавляется в каждый inbox начиная с
    задачи 8, и ассерты задачи 7 про собеседников иначе ломаются на ровном месте."""
    return [f for f in body["friends"] if f["device_id"] != "npc-spirit"]


class TestInbox:
    def test_unregistered_device_is_404_without_side_effects(self, tmp_path, monkeypatch):
        """Соц-слой профили не создаёт: нет строки в players — 404."""
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        r = client.get("/api/social/inbox", params={"device_id": "dev-ghost"})
        assert r.status_code == 404 and r.json()["detail"] == "not_registered", r.text
        for table in ("friend_edges", "messages", "spirit_messages", "social_state"):
            assert _count(srv, "SELECT COUNT(*) AS c FROM %s" % table) == 0, table

    def test_missing_device_id_is_422(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        assert client.get("/api/social/inbox").status_code == 422

    def test_response_shape(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, b, a, "Спасибо за карту!")
        _player(client, "Николя", "dev-z")   # заявка, которую никто не принял
        client.post("/api/friend/request", json={"device_id": "dev-z", "target_nick": "Варда"})
        # last_seen пишут игровые роуты (_upsert_player из brew-check/discover/
        # vein/find/player/register/house), а НЕ POST /api/me — которым тесты и
        # регистрируют. Поэтому значение сеется напрямую: проверяем, что inbox
        # отдаёт живое поле players, а не заглушку "".
        conn = srv.get_db()
        try:
            conn.execute("UPDATE players SET last_seen = ? WHERE device_id = ?",
                         (srv._today(), b))
            conn.commit()
        finally:
            conn.close()
        body = _inbox(client, a)
        assert body["ok"] is True
        assert body["friend_limit"] == srv.FRIEND_MAX
        assert body["unread_total"] == 1
        assert body["requests_total"] == 1
        f = _humans(body)[0]
        assert f["device_id"] == b and f["nick"] == "Мира"
        assert f["unread"] == 1 and f["last_msg_preview"] == "Спасибо за карту!"
        assert f["last_msg_at"], f
        assert f["avatar"], f
        assert f["last_seen"] == srv._today(), f
        inc = body["incoming"][0]
        assert inc["device_id"] == "dev-z" and inc["nick"] == "Николя"
        assert inc["requested_at"], inc
        assert inc["avatar"], inc
        assert inc["last_seen"] == "", "NULL last_seen нормализуется в пустую строку"

    def test_outgoing_requests(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        _ask(client, "Мира")
        body = _inbox(client, "dev-a")
        assert [o["nick"] for o in body["outgoing"]] == ["Мира"], body["outgoing"]
        assert _humans(body) == [], "pending не считается другом"
        assert body["requests_total"] == 0, "requests_total — про ВХОДЯщие"

    def test_sorted_by_last_message_then_nick(self, tmp_path, monkeypatch):
        """Светик первым (задача 8), дальше по последнему сообщению, пустые по нику.

        Часы подменяются и двигаются между отправками: sent_at хранится с
        точностью до секунды, и без этого три сообщения попали бы в одну
        секунду — сортировка выродилась бы в ничью, которую разрешает ник, и
        тест зелёным прошёл бы даже на отсутствующем ключе last_msg_at.
        """
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        for nick, dev in (("Аня", "dev-1"), ("Боря", "dev-2"), ("Вера", "dev-3")):
            _player(client, nick, dev)
            client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": nick})
            client.post("/api/friend/respond",
                        json={"device_id": dev, "requester_device": "dev-a", "accept": True})
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 10)
        _send(client, "dev-3", "dev-a", "от Веры")
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 20)
        _send(client, "dev-1", "dev-a", "от Ани")       # свежее Веры
        # у Бори сообщений нет: пустой last_msg_at обязан уйти в конец
        assert [f["nick"] for f in _humans(_inbox(client, "dev-a"))] == \
            ["Аня", "Вера", "Боря"]
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 30)
        _send(client, "dev-2", "dev-a", "Боря ответил")
        assert [f["nick"] for f in _humans(_inbox(client, "dev-a"))] == \
            ["Боря", "Аня", "Вера"]

    def test_unread_ignores_own_messages(self, tmp_path, monkeypatch):
        """Бейдж направлен в получателя: свои не считаются, чужие — да.

        read_at при вставке NULL, поэтому у b непрочитаны ОБА моих сообщения,
        а у меня — одно его. Переставить `from_device != ?` на `= ?` — и обе
        цифры поменяются местами, тест краснеет.
        """
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, a, b, "моё первое")
        _send(client, a, b, "моё второе")
        _send(client, b, a, "чужое")
        assert _inbox(client, a)["unread_total"] == 1
        mine = next(f for f in _inbox(client, a)["friends"] if f["device_id"] == b)
        assert mine["unread"] == 1, mine
        theirs = next(f for f in _inbox(client, b)["friends"] if f["device_id"] == a)
        assert theirs["unread"] == 2, "для собеседника оба моих сообщения непрочитаны"

    def test_preview_truncated_to_msg_preview_len(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, b, a, "ы" * 500)
        f = _humans(_inbox(client, a))[0]
        assert len(f["last_msg_preview"]) == srv.MSG_PREVIEW_LEN, len(f["last_msg_preview"])
        # полная лента не обрезана: превью — только витрина
        full = client.get("/api/messages", params={"device_id": a, "peer_device": b}).json()
        assert len(full["messages"][0]["body"]) == srv.MSG_MAX_LEN

    def test_rename_visible_immediately(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        client.post("/api/me", json={"device_id": b, "nick": "Мира Вторая"})
        f = _humans(_inbox(client, a))[0]
        assert f["nick"] == "Мира Вторая", f
        assert f["device_id"] == b, "device_id стабилен, ник — витрина"

    def test_prune_by_age_and_by_tail(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        a, b = _befriend(srv, client)
        c, d = _befriend(srv, client, nick_a="Третья", dev_a="dev-c",
                         nick_b="Четвёртая", dev_b="dev-d")
        # старое сообщение (31 день) — глобальная уборка по возрасту
        conn = srv.get_db()
        try:
            conn.execute(
                "INSERT INTO messages (pair_key, from_device, body, sent_at, read_at) "
                "VALUES (?,?,?,?,?)",
                (srv.canonical_pair_key(a, b), b, "древнее",
                 srv._date_minus(srv.MSG_RETENTION_DAYS + 1), srv._now_iso()))
            # хвост 205 сообщений в паре c-d: обрезается до MSG_KEEP_PER_PAIR
            pk = srv.canonical_pair_key(c, d)
            for i in range(srv.MSG_KEEP_PER_PAIR + 5):
                conn.execute(
                    "INSERT INTO messages (pair_key, from_device, body, sent_at, read_at) "
                    "VALUES (?,?,?,?,?)", (pk, d, "tail%03d" % i, srv._now_iso(), srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        # Инбоксом обращается УЧАСТНИК обрезаемой пары: хвосты чистятся только
        # по парям того, кто позвал (глобальная уборка по возрасту — по всем).
        # Вызов от имени a оставил бы пару c-d нетронутой, и проверка хвоста
        # была бы проверкой «ничего не произошло».
        _inbox(client, c)
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE body = 'древнее'") == 0
        tail = _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE pair_key = ?",
                      (srv.canonical_pair_key(c, d),))
        assert tail == srv.MSG_KEEP_PER_PAIR, tail
        # обрезан СТАРЫЙ конец, а не свежий
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE body = 'tail000'") == 0
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE body = 'tail204'") == 1
        # уборка по возрасту глобальна: «древнее» лежит в паре a-b, а позвал c
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE pair_key = ?",
                      (srv.canonical_pair_key(a, b),)) == 0, "в паре a-b было только древнее"

    def test_prune_leaves_short_threads_alone(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, b, a, "живое")
        _inbox(client, a)
        _inbox(client, b)
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages") == 1

    def test_social_state_day_moves_with_clock(self, tmp_path, monkeypatch):
        """social_state.last_inbox_day — основа триггера «return» (задача 8)."""
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        conn = srv.get_db()
        try:
            day = conn.execute(
                "SELECT last_inbox_day FROM social_state WHERE device_id='dev-a'"
            ).fetchone()["last_inbox_day"]
        finally:
            conn.close()
        assert day == "2026-10-07", day
        clock["now"] = _dt.datetime(2026, 10, 9, 8, 0)
        _inbox(client, "dev-a")
        conn = srv.get_db()
        try:
            rows = conn.execute("SELECT last_inbox_day FROM social_state").fetchall()
        finally:
            conn.close()
        assert len(rows) == 1 and rows[0]["last_inbox_day"] == "2026-10-09", rows

    def test_prune_age_boundary_is_exclusive(self, tmp_path, monkeypatch):
        """Граница `<`, а не `<=`: строке ровно MSG_RETENTION_DAYS дней — жить.

        Возврат `_social_prune` к «<=» краснит этот тест, но молчит в
        test_prune_by_age_and_by_tail: там сиду на сутки за границей, и обе
        записи удаляются одинаково. Граничный sent_at — ровно строка
        _date_minus(N) без времени: сравнение лексикографическое, и «<» её
        сохраняет, «<=» — уже нет.
        """
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        a, b = _befriend(srv, client)
        conn = srv.get_db()
        try:
            conn.execute(
                "INSERT INTO messages (pair_key, from_device, body, sent_at) "
                "VALUES (?,?,?,?)",
                (srv.canonical_pair_key(a, b), b, "ровно на границе",
                 srv._date_minus(srv.MSG_RETENTION_DAYS)))
            conn.execute(
                "INSERT INTO messages (pair_key, from_device, body, sent_at) "
                "VALUES (?,?,?,?)",
                (srv.canonical_pair_key(a, b), b, "за границей",
                 srv._date_minus(srv.MSG_RETENTION_DAYS + 1) + "T00:00:01"))
            conn.commit()
        finally:
            conn.close()
        _inbox(client, a)
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE body = 'ровно на границе'") == 1
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE body = 'за границей'") == 0

    def test_preview_is_a_single_line(self, tmp_path, monkeypatch):
        """Превью в строке друга — один Label: перенос разорвал бы её.

        Тело при этом не трогается: лента переводы строк сохраняет по спеке,
        поэтому выпрямление живёт в витрине, а не в _clean_message_body.
        """
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, b, a, "раз\nдва\tтри")
        f = _humans(_inbox(client, a))[0]
        assert f["last_msg_preview"] == "раз два три", repr(f["last_msg_preview"])
        full = client.get("/api/messages", params={"device_id": a, "peer_device": b}).json()
        assert full["messages"][0]["body"] == "раз\nдва\tтри", full["messages"][0]["body"]

    def test_last_msg_at_is_the_preview_row_date(self, tmp_path, monkeypatch):
        """Дата в строке друга — от того же сообщения, что и превью.

        Часы идут назад (NTP-перевод), поэтому MAX(sent_at) указывает на
        предпоследнее письмо, а MAX(id) — на последнее. Отдельный MAX(sent_at)
        в агрегации показал бы «новое» сообщение датированным старше
        предыдущего; этот тест краснеет на его возврате.
        """
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0, 10)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        a, b = _befriend(srv, client)
        _send(client, b, a, "первое")
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 5)
        _send(client, b, a, "второе")
        f = _humans(_inbox(client, a))[0]
        assert f["last_msg_preview"] == "второе", f
        assert f["last_msg_at"] == "2026-10-07T12:00:05", f["last_msg_at"]

    def test_requests_sorted_by_recency_then_nick(self, tmp_path, monkeypatch):
        """Списки заявок упорядочены: свежие первыми, ничья — по нику.

        По одному элементу ключ не проверить: с одной входящей и одной
        исходящей удалённые sort-строки оставляли набор зелёным. Порядок
        вставки здесь намеренно НЕ совпадает с ожидаемым ни по часам, ни по
        нику (Вера раньше Бори при равной секунде, Гриша раньше Даны).
        """
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        for nick, dev in (("Аня", "dev-1"), ("Боря", "dev-2"), ("Вера", "dev-3"),
                          ("Гриша", "dev-4"), ("Дана", "dev-5")):
            _player(client, nick, dev)
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 20)
        _ask(client, "Варда", device_id="dev-3")
        _ask(client, "Варда", device_id="dev-2")
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 10)
        _ask(client, "Варда", device_id="dev-1")
        _ask(client, "Гриша")
        clock["now"] = _dt.datetime(2026, 10, 7, 12, 0, 20)
        _ask(client, "Дана")
        body = _inbox(client, "dev-a")
        assert [i["nick"] for i in body["incoming"]] == ["Боря", "Вера", "Аня"], body["incoming"]
        assert [o["nick"] for o in body["outgoing"]] == ["Дана", "Гриша"], body["outgoing"]
        assert body["requests_total"] == 3, body
        assert _humans(body) == [], "pending не считается другом"


class _FakeSpiritLLM:
    """Провайдер задан, ключ задан — сервер обязан попытаться сгенерировать."""

    def __init__(self, body="Свет твоей колбы сегодня особенно тёплый.", fail=False):
        self.provider = "openrouter"
        self.api_key = "test-key"
        self.models = ["test-model"]
        self.body = body
        self.fail = fail
        self.calls = 0
        self.last_context = None

    def generate_spirit_message(self, context, timeout=0):
        self.calls += 1
        self.last_context = context
        if self.fail:
            return {}
        return {"body": self.body}


class _NoSpiritLLM:
    """local/off провайдер: бюджет LLM не тратится, сразу шаблон."""
    provider = "local"
    api_key = ""
    models = []

    def generate_spirit_message(self, context, timeout=0):
        raise AssertionError("при provider=local сервер не должен звать LLM")


def _spirit_rows(srv, device_id=None):
    conn = srv.get_db()
    try:
        q = ("SELECT device_id, day, trigger_id, body, source, message_id "
             "FROM spirit_messages")
        rows = conn.execute(q + " ORDER BY day").fetchall() if device_id is None \
            else conn.execute(q + " WHERE device_id = ? ORDER BY day",
                              (device_id,)).fetchall()
    finally:
        conn.close()
    return [dict(r) for r in rows]


def _seed_visit(srv, host, visitor, day):
    conn = srv.get_db()
    try:
        conn.execute("INSERT OR IGNORE INTO house_visits (host_device, visitor_device, day) "
                     "VALUES (?,?,?)", (host, visitor, day))
        conn.commit()
    finally:
        conn.close()


def _seed_discovery(srv, device_id, pair_key, at):
    conn = srv.get_db()
    try:
        conn.execute("INSERT OR IGNORE INTO personal_discoveries "
                     "(device_id, pair_key, discovered_at) VALUES (?,?,?)",
                     (device_id, pair_key, at))
        conn.commit()
    finally:
        conn.close()


class TestSpirit:
    def test_spirit_is_first_friend_and_not_a_player(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Мира", "dev-b")
        client.post("/api/friend/request", json={"device_id": "dev-a", "target_nick": "Мира"})
        client.post("/api/friend/respond",
                    json={"device_id": "dev-b", "requester_device": "dev-a", "accept": True})
        body = _inbox(client, "dev-a")
        assert body["friends"][0]["device_id"] == "npc-spirit", body["friends"]
        assert body["friends"][0]["nick"] == srv.SPIRIT_NICK
        # строки в players для Светика НЕТ: иначе он попал бы в /api/rating
        # и в поиск по нику как живой игрок
        conn = srv.get_db()
        try:
            row = conn.execute(
                "SELECT 1 FROM players WHERE device_id = 'npc-spirit'").fetchone()
        finally:
            conn.close()
        assert row is None
        rating = client.get("/api/rating").json()["rows"]
        assert all(r["nick"] != srv.SPIRIT_NICK for r in rating), rating

    def test_spirit_showcase_comes_from_constants(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        f = _inbox(client, "dev-a")["friends"][0]
        assert f["device_id"] == "npc-spirit"
        assert f["nick"] == srv.SPIRIT_NICK, f
        # last_seen у духа — сегодня: клиент рисует «всегда рядом», а не
        # фейковый «онлайн» из даты (спека §6.6)
        assert f["last_seen"] == "2026-10-07", f
        assert f["avatar"], f

    def test_no_event_no_message(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        assert _spirit_rows(srv) == [], "день без письма нормален"
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages") == 0

    def test_one_message_per_day_and_no_second_llm_call(self, tmp_path, monkeypatch):
        fake = _FakeSpiritLLM()
        srv = _srv(tmp_path, monkeypatch, llm=fake)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _player(client, "Гость", "dev-g")
        _inbox(client, "dev-a")
        _inbox(client, "dev-a")
        _inbox(client, "dev-a")
        assert fake.calls == 1, "идемпотентно: LLM не зовётся повторно"
        rows = _spirit_rows(srv, "dev-a")
        assert len(rows) == 1, rows
        assert rows[0]["trigger_id"] == "guest" and rows[0]["source"] == "llm"
        assert rows[0]["message_id"] > 0, rows[0]
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages WHERE id = ?",
                      (rows[0]["message_id"],)) == 1
        assert _count(srv, "SELECT COUNT(*) AS c FROM messages") == 1

    def test_guest_trigger_names_the_visitor(self, tmp_path, monkeypatch):
        fake = _FakeSpiritLLM()
        srv = _srv(tmp_path, monkeypatch, llm=fake)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Гость", "dev-g")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _inbox(client, "dev-a")
        assert fake.last_context["trigger_id"] == "guest", fake.last_context
        assert fake.last_context["trigger_detail"] == "Гость", fake.last_context
        assert fake.last_context["nick"] == "Варда", fake.last_context
        assert fake.last_context["weekday"], fake.last_context

    def test_unread_includes_spirit(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Гость", "dev-g")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        body = _inbox(client, "dev-a")
        assert body["unread_total"] == 1, body
        assert body["friends"][0]["unread"] == 1, body["friends"][0]
        # открытие ленты Светика гасит бейдж: отдельного «mark read» нет
        r = client.get("/api/messages",
                       params={"device_id": "dev-a", "peer_device": "npc-spirit"})
        assert r.status_code == 200, r.text
        assert [m["body"] for m in r.json()["messages"]], r.json()
        assert all(m["from_me"] is False for m in r.json()["messages"])
        assert _inbox(client, "dev-a")["unread_total"] == 0

    def test_template_fallback_when_llm_fails(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM(fail=True))
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Гость", "dev-g")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows[0]["source"] == "template", rows
        assert "Варда" in rows[0]["body"], rows[0]
        assert "{" not in rows[0]["body"] and "}" not in rows[0]["body"], rows[0]

    def test_local_provider_does_not_spend_budget(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_NoSpiritLLM())
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Гость", "dev-g")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows and rows[0]["source"] == "template", rows
        # Гейт проверяем напрямую: через inbox он невидим, потому что
        # generate_spirit_message у local-провайдера возвращает {} и без него.
        conn = srv.get_db()
        try:
            assert srv._reserve_spirit_llm(conn, srv._today()) is False, \
                "local-провайдер не резервирует бюджет весточек"
        finally:
            conn.close()

    def test_global_daily_llm_cap(self, tmp_path, monkeypatch):
        """Свой гейт, не общая _reserve_llm_generation: весточки не едят квоту веществ."""
        fake = _FakeSpiritLLM()
        srv = _srv(tmp_path, monkeypatch, llm=fake)
        monkeypatch.setattr(srv, "SPIRIT_LLM_PER_DAY_GLOBAL", 1)
        client = _client(srv)
        today = srv._today()
        for nick, dev in (("Варда", "dev-a"), ("Мира", "dev-b")):
            _player(client, nick, dev)
            _player(client, "Гость " + nick, "dev-g-" + dev)
            _seed_visit(srv, dev, "dev-g-" + dev, today)
        _inbox(client, "dev-a")
        _inbox(client, "dev-b")
        rows = {r["device_id"]: r["source"] for r in
                (_spirit_rows(srv, "dev-a") + _spirit_rows(srv, "dev-b"))}
        assert sorted(rows.values()) == ["llm", "template"], rows
        assert fake.calls == 1, "второму игроку LLM уже не зовётся"

    def test_return_beats_guest(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        clock = {"now": _dt.datetime(2026, 10, 1, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Гость", "dev-g")
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _inbox(client, "dev-a")          # гость есть, «возврата» нет → guest
        clock["now"] = _dt.datetime(2026, 10, 5, 12, 0)
        _seed_visit(srv, "dev-a", "dev-g", srv._today())
        _inbox(client, "dev-a")          # гость снова, но 4 дня не заходил → return
        rows = _spirit_rows(srv, "dev-a")
        assert len(rows) == 2, rows
        assert rows[0]["trigger_id"] == "guest", rows[0]
        assert rows[-1]["trigger_id"] == "return", rows[-1]

    def test_return_ignores_last_seen_from_game_routes(self, tmp_path, monkeypatch):
        """Игрок мог варить и заглядывать в дом (это пишет players.last_seen через
        _upsert_player), но в ленту не заходить. last_seen сегодня, а весточка
        «return» всё равно обязана выйти: источник — social_state.last_inbox_day."""
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        clock = {"now": _dt.datetime(2026, 10, 1, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        clock["now"] = _dt.datetime(2026, 10, 6, 9, 0)
        conn = srv.get_db()
        try:
            # Так выглядит строка игрока после игрового роута: _upsert_player
            # ставит last_seen = сегодня. POST /api/me его не трогает (set_me
            # пишет только nick), поэтому сеём напрямую.
            conn.execute("UPDATE players SET last_seen = ? WHERE device_id = 'dev-a'",
                         (srv._today(),))
            conn.commit()
        finally:
            conn.close()
        conn = srv.get_db()
        try:
            last_seen = conn.execute(
                "SELECT last_seen FROM players WHERE device_id='dev-a'").fetchone()["last_seen"]
        finally:
            conn.close()
        assert last_seen == "2026-10-06", last_seen
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows[-1]["trigger_id"] == "return", rows

    def test_first_inbox_is_not_return(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        assert _spirit_rows(srv, "dev-a") == [], \
            "строки в social_state нет (первый вход) — триггер не срабатывает"

    def test_return_needs_full_three_days(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        clock = {"now": _dt.datetime(2026, 10, 1, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        clock["now"] = _dt.datetime(2026, 10, 3, 12, 0)   # 2 дня с последней отметки — мало
        _inbox(client, "dev-a")
        assert _spirit_rows(srv, "dev-a") == []
        # Каждый inbox переставляет отметку, поэтому отсчёт «3 дня» идёт от
        # 2026-10-03, а не от первого входа. Это же тест ловит и порядок шагов:
        # если _social_mark_seen встанет ДО _ensure_spirit_message, на 6-е число
        # days будет 0 и весточка «return» не выйдет.
        clock["now"] = _dt.datetime(2026, 10, 6, 12, 0)   # 3 дня от отметки — сработал
        _inbox(client, "dev-a")
        assert [r["trigger_id"] for r in _spirit_rows(srv, "dev-a")] == ["return"]

    def test_all_triggers_are_covered_by_pool(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        triggers = ("return", "guest", "vein_find", "sigil_milestone",
                    "sigil_craft", "first_brew")
        assert set(srv._SPIRIT_FALLBACK) == set(triggers), sorted(srv._SPIRIT_FALLBACK)
        for t in triggers:
            pool = srv._SPIRIT_FALLBACK[t]
            assert len(pool) >= 5, (t, len(pool))
            for phrase in pool:
                assert "{nick}" in phrase, (t, phrase)
                body = srv._spirit_fallback("dev-a", "2026-10-07", t, "Варда", "Гость")
                assert "{" not in body and "}" not in body, (t, body)
                assert len(body) <= srv.SPIRIT_BODY_MAX, (t, len(body))

    def test_fallback_is_deterministic(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        a = srv._spirit_fallback("dev-a", "2026-10-07", "guest", "Варда", "Гость")
        b = srv._spirit_fallback("dev-a", "2026-10-07", "guest", "Варда", "Гость")
        assert a == b, "тот же день и устройство — та же фраза (перезапуск не мельтешит)"
        assert "{nick}" not in a and "{detail}" not in a
        assert "Варда" in a and "Гость" in a, a
        # другой день — другая фраза хотя бы иногда; гарантируем только, что
        # выбор не вырождается в константу на все дни
        week = {srv._spirit_fallback("dev-a", "2026-10-%02d" % d, "guest",
                                     "Варда", "Гость") for d in range(1, 15)}
        assert len(week) > 1, week

    def test_body_validation_rejects_bad_llm_output(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _player(client, "Сосед", "dev-z")
        conn = srv.get_db()
        try:
            good = "Колба сегодня светится ровно, {nick}".replace("{nick}", "Варда")
            assert srv._spirit_clean_body(conn, good, "Варда", "dev-a", "") == good
            for bad in ("", "   ", "две\nстроки", "два\r\nперевода",
                        "твой device_id dev-a виден",
                        "код 123456",
                        "Сосед заходил сегодня",       # ник третьего игрока
                        "ы" * 400):
                assert srv._spirit_clean_body(conn, bad, "Варда", "dev-a", "") == "", bad
            # длина за границей: обрезаем по последнему пробелу внутри лимита,
            # а не по самому лимиту. Пока long_ok короче SPIRIT_BODY_MAX, ветка
            # обрезки не исполняется ни при какой правке — поэтому текст ниже
            # гарантированно длиннее лимита, и краснеет он и на удалении ветки,
            # и на срезе «по индексу, не по слову».
            tail = "и свет на полке держится ровно"
            long_ok = ("Светик смотрит на полку с колбами и тихо радуется, "
                       "что {nick} сегодня снова здесь, в тёплой лаборатории, "
                       ).replace("{nick}", "Варда") + tail * 6
            assert srv.SPIRIT_BODY_MAX < len(long_ok), len(long_ok)
            got = srv._spirit_clean_body(conn, long_ok, "Варда", "dev-a", "")
            assert got and got == long_ok[:srv.SPIRIT_BODY_MAX].rsplit(" ", 1)[0], got
            assert len(got) < srv.SPIRIT_BODY_MAX, len(got)
            # ник из detail — не «чужой ник»: гостя в его же весточке называть
            # можно. Без этой оговорки каждая LLM-весточка guest молча уходила
            # бы на шаблон, и тест выше («Сосед заходил» → '') этого не ловил бы.
            with_detail = "К тебе заходил Сосед, Варда — колбы ещё тёплые."
            assert srv._spirit_clean_body(conn, with_detail, "Варда", "dev-a",
                                          "Сосед") == with_detail, with_detail
        finally:
            conn.close()

    def test_vein_find_and_sigil_triggers(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch, llm=_FakeSpiritLLM())
        clock = {"now": _dt.datetime(2026, 10, 7, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _seed_discovery(srv, "dev-a", "вода|огонь", srv._now_iso())
        _inbox(client, "dev-a")
        assert [r["trigger_id"] for r in _spirit_rows(srv, "dev-a")] == ["vein_find"]
        # следующий день — следующий триггер
        clock["now"] = _dt.datetime(2026, 10, 8, 12, 0)
        conn = srv.get_db()
        try:
            conn.execute("INSERT OR IGNORE INTO sigil_crafts (device_id, craft_id, rarity, "
                         "llm_name, crafted_at) VALUES (?,?,?,?,?)",
                         ("dev-a", "c1", "common", "Сигил Утра", srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows[-1]["trigger_id"] == "sigil_craft", rows[-1]
        assert rows[-1]["day"] == "2026-10-08", rows[-1]
        assert rows[-1]["body"], rows[-1]
        # 10-09 — sigil_milestone, 10-10 — first_brew: оба SQL-запроса обязаны
        # исполняться хотя бы раз. Опечатка в колонке здесь даёт OperationalError
        # внутри _spirit_trigger, а это 500 всего inbox — «нет весточки» был бы
        # безобидной подменой, и тест бы о ней не сообщил.
        clock["now"] = _dt.datetime(2026, 10, 9, 12, 0)
        conn = srv.get_db()
        try:
            conn.execute("INSERT OR IGNORE INTO sigil_milestones (device_id, set_id, tier, "
                         "claimed_at) VALUES (?,?,?,?)",
                         ("dev-a", "major", 1, srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows[-1]["trigger_id"] == "sigil_milestone", rows[-1]
        assert rows[-1]["day"] == "2026-10-09", rows[-1]
        clock["now"] = _dt.datetime(2026, 10, 10, 12, 0)
        conn = srv.get_db()
        try:
            # first_at с явным значением: дефолт sqlite — datetime('now') в UTC,
            # а тест подменяет только _now_dt, так что на «сегодня» он бы не лёг.
            conn.execute("INSERT OR IGNORE INTO resonance_seen (pair_key, brewer_key, "
                         "first_at) VALUES (?,?,?)",
                         ("p1", "dev-a", srv._now_iso()))
            conn.commit()
        finally:
            conn.close()
        _inbox(client, "dev-a")
        rows = _spirit_rows(srv, "dev-a")
        assert rows[-1]["trigger_id"] == "first_brew", rows[-1]
        assert rows[-1]["day"] == "2026-10-10", rows[-1]

    def test_spirit_edge_cannot_be_removed(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        _player(client, "Варда", "dev-a")
        _inbox(client, "dev-a")
        conn = srv.get_db()
        try:
            n = conn.execute(
                "SELECT COUNT(*) AS c FROM friend_edges WHERE state='accepted'").fetchone()["c"]
        finally:
            conn.close()
        assert n == 1, "ребро Светика создаётся лениво при первом inbox"
        # Светик не занимает слот FRIEND_MAX
        conn = srv.get_db()
        try:
            assert srv._social_friend_count(conn, "dev-a") == 0
        finally:
            conn.close()
