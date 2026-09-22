"""Дневной круг (v29): вечный суммарный счёт очков цели дня."""
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import server as srv  # noqa: E402


def _client_for(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "circle.db"))
    return TestClient(srv.app)


def _seed_scores(db_path):
    import sqlite3
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO challenge_scores (day, device_id, nick, points) VALUES (?, ?, ?, ?)",
        ("2026-09-10", "dev1", "Алхимик", 7),
    )
    conn.execute(
        "INSERT INTO challenge_scores (day, device_id, nick, points) VALUES (?, ?, ?, ?)",
        ("2026-09-11", "dev1", "Алхимик", 5),
    )
    conn.execute(
        "INSERT INTO challenge_scores (day, device_id, nick, points) VALUES (?, ?, ?, ?)",
        ("2026-09-11", "dev2", "Другой", 3),
    )
    conn.commit()
    conn.close()


class TestCirclePointsTotal:
    def test_total_sums_all_days(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch)
        with c:
            r = c.get("/api/challenge", params={"device_id": "dev1"})
            assert r.status_code == 200
            _seed_scores(str(tmp_path / "circle.db"))
            r = c.get("/api/challenge", params={"device_id": "dev1"})
            assert r.status_code == 200
            body = r.json()
            assert body["ok"] is True
            assert body["my_points_total"] == 12
            # чужой счёт не примешивается
            r2 = c.get("/api/challenge", params={"device_id": "dev2"})
            assert r2.json()["my_points_total"] == 3

    def test_total_zero_unknown(self, tmp_path, monkeypatch):
        c = _client_for(tmp_path, monkeypatch)
        with c:
            r = c.get("/api/challenge", params={"device_id": "nobody"})
            assert r.status_code == 200
            body = r.json()
            assert body["my_points_total"] == 0
            assert body["my_points"] == 0
