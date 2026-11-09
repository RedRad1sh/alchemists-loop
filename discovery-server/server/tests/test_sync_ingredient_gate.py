"""/api/sync/package не выдаёт права на то, чего устройство не варило.

Без гейта: inventory_slugs из публичного /api/world → recovery отдаёт всю книгу
рецептов и пишет element-гранты, после чего /api/discover пускает любой
генеративный ингредиент. local_learn — то же через part_b.recipes.
"""
import os
import sqlite3
import sys

from fastapi.testclient import TestClient

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))

from test_recovery_defs import materialize_pair  # noqa: E402


def _setup(tmp_path, monkeypatch):
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "gate.db"))
    return srv


def _db(srv):
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _pkg(device, recipes=(), inventory=()):
    return {
        "device_id": device, "schema_version": 4, "client_rev": 1,
        "anchor_accrual_ts": 0.0,
        "part_b": {"recipes": list(recipes), "elements": []},
        "part_c": {"inventory_slugs": list(inventory)},
    }


def _element_refs(body):
    return {g["ref"] for g in body["grants"] if g["kind"] == "element"}


def test_recovery_ignores_generated_slugs_the_device_never_got(tmp_path, monkeypatch):
    srv = _setup(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        conn = _db(srv)
        materialize_pair(conn, "ice", "gold", "wonder")
        conn.close()
        body = client.post("/api/sync/package", json=_pkg("devThief", inventory=["wonder"])).json()
    assert body["recovered"] == []
    assert "wonder" not in _element_refs(body)


def test_recovery_still_restores_slugs_the_device_owns(tmp_path, monkeypatch):
    srv = _setup(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        conn = _db(srv)
        key = materialize_pair(conn, "ice", "gold", "wonder")
        conn.execute(
            "INSERT INTO device_grants (device_id, kind, ref, source, granted_at) "
            "VALUES ('devOwner', 'element', 'wonder', 'world_first', '2026-11-09')"
        )
        conn.commit()
        conn.close()
        body = client.post("/api/sync/package", json=_pkg("devOwner", inventory=["wonder"])).json()
    assert any(d["pair_key"] == key for d in body["recovered"])


def test_local_learn_rejects_pair_with_unowned_generated_ingredient(tmp_path, monkeypatch):
    srv = _setup(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        conn = _db(srv)
        materialize_pair(conn, "ice", "gold", "wonder")
        key2 = materialize_pair(conn, "fire", "wonder", "marvel")
        conn.close()
        body = client.post("/api/sync/package", json=_pkg("devThief", recipes=[
            {"pair_key": key2, "a": "fire", "b": "wonder", "out": "marvel"},
        ])).json()
    assert body["accepted"] == 0 and body["rejected"] == 1
    assert "marvel" not in _element_refs(body)


def test_local_learn_accepts_a_chain_in_any_order(tmp_path, monkeypatch):
    # Цепочка ice+gold→wonder, fire+wonder→marvel в одном пакете в обратном
    # порядке: второй рецепт становится законным, как только принят первый.
    srv = _setup(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        conn = _db(srv)
        key1 = materialize_pair(conn, "ice", "gold", "wonder")
        key2 = materialize_pair(conn, "fire", "wonder", "marvel")
        conn.close()
        body = client.post("/api/sync/package", json=_pkg("devChain", recipes=[
            {"pair_key": key2, "a": "fire", "b": "wonder", "out": "marvel"},
            {"pair_key": key1, "a": "gold", "b": "ice", "out": "wonder"},
        ])).json()
    assert body["accepted"] == 2 and body["rejected"] == 0
    assert {"wonder", "marvel"} <= _element_refs(body)
