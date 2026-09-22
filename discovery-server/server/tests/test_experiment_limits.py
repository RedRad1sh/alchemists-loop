"""Регрессии Experiment Bench: кеш, quota и локальный fallback не расходуют LLM budget."""

import os
import sys


def _client(tmp_path, monkeypatch, llm):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    from fastapi.testclient import TestClient

    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "experiment.db"))
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    srv.init_db()
    return srv, TestClient(srv.app)


class _ExternalLLM:
    provider = "openrouter"

    def __init__(self):
        self.calls = 0
        self.names = iter(["ПерваяВещь", "ВтораяВещь", "ТретьяВещь", "ЧетвёртаяВещь"])

    def available(self):
        return True

    def generate(self, *args, **kwargs):
        self.calls += 1
        return {"combinable": True, "name": next(self.names)}


class _LocalFallback(_ExternalLLM):
    provider = "local"


class TestExperimentLimits:
    def test_cached_result_does_not_consume_experiment_budget(self, tmp_path, monkeypatch):
        import server as srv

        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
        monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
        monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 100)
        payload = {"a": "dust", "b": "sky", "nick": "A", "device_id": "device-1", "experiment": True}
        with client:
            first = client.post("/api/discover", json=payload)
            assert first.json()["status"] == "created"
            # The second client sees the same durable recipe; this is a cache hit,
            # not another LLM-backed experiment.
            cached = client.post("/api/discover", json={**payload, "nick": "B", "device_id": "device-2"})
            assert cached.json()["status"] == "known"
            row = srv.get_db().execute(
                "SELECT attempts FROM experiment_limits WHERE device_id = ?", ("device-2",)
            ).fetchone()
            assert row is None
            assert llm.calls == 1

    def test_device_quota_and_cooldown_are_durable(self, tmp_path, monkeypatch):
        import server as srv

        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
        monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
        monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 100)
        with client:
            first = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            assert first.json()["status"] == "created"
            limited = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            assert limited.json()["status"] == "rate_limited"
            assert "лимит" in limited.json()["message"].lower()
            assert llm.calls == 1

    def test_cooldown_blocks_only_the_next_external_experiment(self, tmp_path, monkeypatch):
        import server as srv

        llm = _ExternalLLM()
        srv, client = _client(tmp_path, monkeypatch, llm)
        monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 10)
        monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 3600.0)
        monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 100)
        with client:
            first = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            assert first.json()["status"] == "created"
            limited = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            assert limited.json()["status"] == "rate_limited"
            assert "через" in limited.json()["message"].lower()
            assert llm.calls == 1

    def test_local_fallback_does_not_spend_external_quota(self, tmp_path, monkeypatch):
        import server as srv

        llm = _LocalFallback()
        srv, client = _client(tmp_path, monkeypatch, llm)
        monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
        monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 3600.0)
        monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 1)
        with client:
            first = client.post("/api/discover", json={
                "a": "dust", "b": "sky", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            second = client.post("/api/discover", json={
                "a": "sand", "b": "smoke", "nick": "A", "device_id": "device-1", "experiment": True,
            })
            assert first.json()["status"] == "created"
            assert second.json()["status"] == "created"
            assert llm.calls == 2
            conn = srv.get_db()
            assert conn.execute("SELECT COUNT(*) FROM experiment_limits").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM experiment_global_limits").fetchone()[0] == 0
            conn.close()
