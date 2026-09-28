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
        # Финальное ревью (F3): vein-таблицы, которые раньше НЕ чистились при
        # удалении аккаунта. Строки удаляемого устройства + чужого устройства
        # (последнее должно выжить).
        for dev in ("privacy-device", "other-device"):
            conn.execute(
                "INSERT INTO personal_discoveries (device_id, pair_key, discovered_at) "
                "VALUES (?, 'fire|water', '2026-01-01T00:00:00')",
                (dev,),
            )
            conn.execute(
                "INSERT INTO vein_streaks (device_id, cycle_id, count) "
                "VALUES (?, 'vc:privacy-test', 2)",
                (dev,),
            )
            conn.execute(
                "INSERT INTO vein_pour_log (device_id, idempotency_key, processed_at) "
                "VALUES (?, 'k1', '2026-01-01T00:00:00')",
                (dev,),
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
        body = deleted.json()
        assert body["ok"] is True
        assert body["deleted"] is True
        assert body.get("device_id") == "privacy-device"

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
        # F3: все три vein-таблицы вычищены для удалённого устройства…
        for table in ("personal_discoveries", "vein_streaks", "vein_pour_log"):
            assert conn.execute(
                f"SELECT COUNT(*) FROM {table} WHERE device_id = ?", ("privacy-device",)
            ).fetchone()[0] == 0, table
            # …и не тронуты у другого устройства
            assert conn.execute(
                f"SELECT COUNT(*) FROM {table} WHERE device_id = ?", ("other-device",)
            ).fetchone()[0] == 1, table
        conn.close()

        after = client.get(
            "/api/account/export", params={"device_id": "privacy-device"}
        )
        assert after.status_code == 200
        assert after.json()["found"] is False
