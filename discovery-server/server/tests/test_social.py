"""
Социальные интеракции S1: друзья, почтовый ящик, блок, весточки Светика.

Идиома — та же, что в tests/test_house_visits.py (19 из 24 модулей сервера):
in-process TestClient(srv.app) + подмена DB_PATH + явный init_db(). Фикстура
process_server здесь не годится: подпроцесс не даёт подменить ни _now_dt
(уборка почты, триггер «return»), ни get_llm (весточки).
"""

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
    return [(r["name"], r["type"], r["notnull"], r["pk"])
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
            pk = [name for (name, _t, _n, pk) in _columns(conn, "friend_edges") if pk]
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
        assert srv.SPIRIT_RETURN_DAYS == 3
        assert srv.SPIRIT_LLM_PER_DAY_GLOBAL == 200
        assert srv.SPIRIT_BODY_MAX == 200
        # зарезервированный device_id не должен наследовать семантику seed-ботов
        assert not srv.SPIRIT_DEVICE.startswith("bot-")
