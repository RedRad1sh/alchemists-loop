"""Проверка экспорта и удаления персональных связей аккаунта."""

import os
import sqlite3
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "privacy.db"))
    return srv


def test_account_export_and_delete_preserves_world(tmp_path, monkeypatch):
    srv = _srv(tmp_path, monkeypatch)
    client = TestClient(srv.app)
    with client:
        assert client.post(
            "/api/me", json={"device_id": "privacy-device", "nick": "Варда"}
        ).status_code == 200

        conn = sqlite3.connect(srv.DB_PATH)
        conn.execute("UPDATE elements SET author = 'Варда' WHERE slug = 'fire'")
        conn.execute(
            """INSERT INTO world_events
               (pair_key, a, b, out, out_name, discoverer)
               VALUES (?, ?, ?, ?, ?, ?)""",
            ("fire|water", "fire", "water", "steam", "Пар", "Варда"),
        )
        conn.commit()
        conn.close()

        exported = client.get(
            "/api/account/export", params={"device_id": "privacy-device"}
        )
        assert exported.status_code == 200
        body = exported.json()
        assert body["found"] is True
        assert body["data"]["profile"]["nick"] == "Варда"
        assert any(row["slug"] == "fire" for row in body["data"]["discoveries"])

        deleted = client.delete(
            "/api/account", params={"device_id": "privacy-device"}
        )
        assert deleted.status_code == 200
        assert deleted.json() == {"ok": True, "deleted": True}

        conn = sqlite3.connect(srv.DB_PATH)
        assert conn.execute(
            "SELECT COUNT(*) FROM players WHERE device_id = ?", ("privacy-device",)
        ).fetchone()[0] == 0
        assert conn.execute(
            "SELECT author FROM elements WHERE slug = 'fire'"
        ).fetchone()[0] is None
        assert conn.execute(
            "SELECT discoverer FROM world_events WHERE pair_key = 'fire|water'"
        ).fetchone()[0] == "Анонимный алхимик"
        conn.close()

        after = client.get(
            "/api/account/export", params={"device_id": "privacy-device"}
        )
        assert after.status_code == 200
        assert after.json()["found"] is False
