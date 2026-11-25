"""Контракты персональной цели Experiment."""

import json
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import date
from threading import Barrier, Event, Lock

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def quest(tmp_path, monkeypatch):
    import server as srv

    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "quest.db"))
    monkeypatch.setattr(srv.beta_access, "enabled", lambda: False)
    srv.init_db()
    yield srv, TestClient(srv.app)


def _target(client, device="device-a"):
    response = client.post("/api/experiment/target", json={"device_id": device, "nick": "Аня"})
    assert response.status_code == 200, response.text
    return response.json()


def _grant_catalog_except(srv, slug, device="device-a"):
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO device_grants (device_id, kind, ref, source, granted_at) "
            "SELECT ?, 'element', slug, 'test', '2026-11-22T12:00:00Z' "
            "FROM elements WHERE slug != ?",
            (device, slug),
        )


def test_active_goal_survives_server_week_boundary(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    first = _target(client)["target"]
    assert first["cycle_week"] == "2026-W47"
    assert first["status"] == "active"
    assert _target(client)["target"] == first

    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    assert _target(client)["target"] == first
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 1


def test_world_goal_uses_undiscovered_ingredient_not_the_public_seed_allowlist(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    _grant_catalog_except(srv, "steam")
    target = _target(client)["target"]
    assert (target["kind"], target["slug"], target["name"]) == ("world", "steam", "Пар")


def test_empty_world_frontier_uses_llm_even_in_a_world_bucket(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    _grant_catalog_except(srv, "")
    target = _target(client)["target"]
    assert (target["kind"], target["slug"]) == ("llm", "")
    assert target["name"] and target["hint"]
    assert "source_pair" not in target


def test_unavailable_llm_goal_does_not_fall_back_or_claim_slot(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    monkeypatch.setattr(srv, "get_llm", lambda: srv.LLMGenerator(provider="off"))
    data = _target(client, "boundary-21")  # bucket 80, with a nonempty world frontier
    assert (data["ok"], data["status"], data["target"]) == (False, "target_unavailable", None)
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 0


def test_failed_llm_target_allocations_are_refunded_but_cooldown_guarded(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))

    class UnavailableExternalGenerator:
        provider = "openrouter"

        def generate_personal_target(self, seed):
            raise srv.LLMError("provider unavailable")

    monkeypatch.setattr(srv, "get_llm", lambda: UnavailableExternalGenerator())
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 5)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 5)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 60.0)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    first = _target(client, "boundary-21")
    second = _target(client, "boundary-21")

    assert first["status"] == "target_unavailable"
    assert (second["ok"], second["status"], second["target"]) == (False, "rate_limited", None)
    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = ?", ("boundary-21",)
        ).fetchone()[0] == 0
        assert conn.execute("SELECT attempts FROM experiment_global_limits LIMIT 1").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0


def test_llm_target_allocation_respects_existing_external_quota(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    calls = []

    class ExternalGenerator:
        provider = "openrouter"

        def generate_personal_target(self, seed):
            calls.append(seed)
            return {"name": "Рассвет", "hint": "Найди свет после тьмы."}

    monkeypatch.setattr(srv, "get_llm", lambda: ExternalGenerator())
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 1)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO experiment_limits (day, device_id, attempts, last_at) VALUES (?, ?, 1, 0)",
            (srv._today(), "boundary-21"),
        )
        conn.execute(
            "INSERT INTO experiment_global_limits (day, attempts) VALUES (?, 1)",
            (srv._today(),),
        )

    result = _target(client, "boundary-21")

    assert (result["ok"], result["status"], result["target"]) == (False, "rate_limited", None)
    assert calls == []
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0


def test_llm_target_allocation_releases_writer_lock_during_provider_call(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    monkeypatch.setattr(srv, "DB_BUSY_TIMEOUT_SEC", 0.2)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")
    entered = Event()
    release = Event()

    class PausedGenerator:
        def generate_personal_target(self, seed):
            entered.set()
            if not release.wait(5):
                raise RuntimeError("provider release timed out")
            return {"name": "Рассвет", "hint": "Найди свет после тьмы."}

    monkeypatch.setattr(srv, "get_llm", lambda: PausedGenerator())
    with ThreadPoolExecutor(max_workers=1) as pool:
        pending = pool.submit(_target, client, "boundary-21")
        try:
            assert entered.wait(2)
            with closing(srv.get_db()) as conn, conn:
                conn.execute("BEGIN IMMEDIATE")
                conn.execute("UPDATE players SET nick = nick WHERE device_id = ?", ("boundary-21",))
        finally:
            release.set()
        result = pending.result(timeout=5)

    assert result["ok"] is True
    assert result["target"]["kind"] == "llm"


def test_concurrent_next_slot_allocations_share_one_llm_target(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    with closing(srv.get_db()) as conn, conn:
        conn.execute("BEGIN IMMEDIATE")
        previous = srv._insert_personal_target(conn, "boundary-21", "2026-W47", 1, {
            "kind": "llm", "target_slug": None, "target_name": "Старая цель",
            "target_hint": "Завершённая цель прошлой недели.",
        })
        conn.execute(
            "UPDATE personal_experiment_targets SET status = 'completed', "
            "completed_at = ?, next_eligible_week = '2026-W48' WHERE id = ?",
            ("2026-11-22T12:00:00Z", previous["id"]),
        )
        conn.commit()

    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")
    entered = Event()
    release = Event()
    waiting = Event()
    calls = []
    call_lock = Lock()

    class PausedGenerator:
        provider = "openrouter"

        def generate_personal_target(self, seed):
            with call_lock:
                calls.append(seed)
            entered.set()
            if not release.wait(5):
                raise RuntimeError("provider release timed out")
            return {"name": "Рассвет", "hint": "Найди свет после тьмы."}

    real_wait = srv._wait_for_personal_allocation

    def observed_wait(*args):
        waiting.set()
        return real_wait(*args)

    monkeypatch.setattr(srv, "get_llm", lambda: PausedGenerator())
    monkeypatch.setattr(srv, "_wait_for_personal_allocation", observed_wait)
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(_target, client, "boundary-21")
        try:
            assert entered.wait(2)
            second = pool.submit(_target, client, "boundary-21")
            assert waiting.wait(2)
        finally:
            release.set()
        replies = [first.result(timeout=5), second.result(timeout=5)]

    assert calls == ["boundary-21|2026-W48|2"]
    assert replies[0] == replies[1]
    assert replies[0]["target"]["id"] != previous["id"]
    assert replies[0]["target"]["status"] == "active"
    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT COUNT(*) FROM personal_experiment_targets WHERE device_id = 'boundary-21'"
        ).fetchone()[0] == 2
        assert conn.execute(
            "SELECT sequence FROM personal_experiment_targets WHERE id = ?",
            (replies[0]["target"]["id"],),
        ).fetchone()[0] == 2
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0


def test_stale_personal_allocation_claim_is_reclaimed(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO personal_experiment_allocations "
            "(device_id, sequence, claim_token, claimed_at) VALUES (?, 1, 'stale-token', 0)",
            ("boundary-21",),
        )

    result = _target(client, "boundary-21")

    assert result["ok"] is True
    assert result["target"]["kind"] == "llm"
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0


def test_unexpected_allocation_exception_refunds_quota_and_cleans_claim(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    class BrokenGenerator:
        provider = "openrouter"

        def generate_personal_target(self, seed):
            raise RuntimeError("provider crashed")

    monkeypatch.setattr(srv, "get_llm", lambda: BrokenGenerator())
    with pytest.raises(RuntimeError, match="provider crashed"):
        _target(client, "boundary-21")

    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = 'boundary-21'"
        ).fetchone()[0] == 0
        assert conn.execute("SELECT attempts FROM experiment_global_limits LIMIT 1").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 0


def test_conflicting_allocations_refund_quota_and_clean_claim(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    class ConflictingGenerator:
        provider = "openrouter"

        def generate_personal_target(self, seed):
            return {"name": "Огонь", "hint": "Уже существует в мировом каталоге."}

    monkeypatch.setattr(srv, "get_llm", lambda: ConflictingGenerator())
    result = _target(client, "boundary-21")

    assert (result["ok"], result["status"], result["target"]) == (
        False, "target_unavailable", None,
    )
    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = 'boundary-21'"
        ).fetchone()[0] == 0
        assert conn.execute("SELECT attempts FROM experiment_global_limits LIMIT 1").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_allocations").fetchone()[0] == 0


def test_llm_goal_name_conflicting_with_active_personal_target_is_unavailable(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    _grant_catalog_except(srv, "__no_such_slug__", device="existing-device")
    first = _target(client, "existing-device")["target"]
    assert first["kind"] == "llm"

    class ConflictingPersonalGenerator:
        provider = "local"

        def generate_personal_target(self, seed):
            return {"name": first["name"], "hint": first["hint"]}

    monkeypatch.setattr(srv, "get_llm", lambda: ConflictingPersonalGenerator())
    blocked = _target(client, "boundary-21")

    assert (blocked["ok"], blocked["status"], blocked["target"]) == (False, "target_unavailable", None)
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 1


@pytest.fixture
def world_goal(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    _grant_catalog_except(srv, "steam")
    return srv, client, _target(client)["target"]


def _attempt(client, goal, a="fire", b="water", device="device-a", request_id="try-1", **fields):
    response = client.post("/api/experiment/attempt", json={
        "device_id": device, "nick": "Аня", "target_id": goal["id"],
        "request_id": request_id, "a": a, "b": b, **fields,
    })
    assert response.status_code == 200, response.text
    return response.json()


def test_world_goal_completes_once_when_known_recipe_grants_new_element(world_goal):
    srv, client, goal = world_goal
    first = _attempt(client, goal, target_name="Другая цель", target_slug="mist", target_kind="llm")
    assert first["status"] == "known"
    assert first["acquired"] is True
    assert first["discovery"]["slug"] == "steam"
    assert first["target"]["status"] == "completed"
    assert first["target"]["name"] == "Пар"
    assert first["target"]["attempts"] == first["target"]["successful_steps"] == 1
    assert first["target"]["spent_ether"] == first["ether_charged"] == 12
    assert _attempt(client, goal, a="water", b="fire") == first
    assert _attempt(client, goal, a="air", b="water", request_id="after-success")["status"] == "target_stale"
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_attempts").fetchone()[0] == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM device_grants WHERE device_id = 'device-a' "
            "AND ((kind = 'element' AND ref = 'steam') OR (kind = 'recipe' AND ref = 'fire|water'))"
        ).fetchone()[0] == 2


def test_world_goal_existing_personal_result_does_not_charge(world_goal):
    srv, client, goal = world_goal
    result = _attempt(client, goal, a="air", b="water")
    assert result["status"] == "known"
    assert result["acquired"] is False
    assert result["discovery"]["slug"] == "mist"
    assert result["target"]["status"] == "active"
    assert result["target"]["attempts"] == 1
    assert result["target"]["successful_steps"] == 0
    assert result["target"]["spent_ether"] == result["ether_charged"] == 0


def test_world_goal_cached_rejection_does_not_charge(world_goal):
    srv, client, goal = world_goal
    with closing(srv.get_db()) as conn, conn:
        conn.execute("INSERT INTO rejected_pairs(pair_key) VALUES ('air|air')")
    result = _attempt(client, goal, a="air", b="air")
    assert result["status"] == "not_combinable"
    assert result["discovery"] is None
    assert result["target"]["attempts"] == 1
    assert result["target"]["successful_steps"] == result["ether_charged"] == 0


def test_foreign_goal_and_unlearned_seed_ingredient_are_rejected(world_goal):
    srv, client, goal = world_goal
    foreign = _attempt(client, goal, device="device-b")
    assert (foreign["status"], foreign["target"]) == ("target_not_found", None)
    unlearned = _attempt(client, goal, a="steam", b="air")
    assert unlearned["status"] == "ingredient_not_granted"
    assert _target(client)["target"]["attempts"] == 0


def test_ingredient_rejection_replays_after_player_later_learns_ingredient(world_goal):
    srv, client, goal = world_goal
    rejected = _attempt(client, goal, a="steam", b="air", request_id="late-grant")
    assert rejected["status"] == "ingredient_not_granted"
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO device_grants(device_id, kind, ref, source, granted_at) "
            "VALUES ('device-a', 'element', 'steam', 'test', '2026-11-22T12:00:00Z')"
        )

    assert _attempt(client, goal, a="steam", b="air", request_id="late-grant") == rejected
    assert _target(client)["target"]["attempts"] == 0


def test_replay_cannot_be_read_by_another_device(world_goal):
    srv, client, goal = world_goal
    completed = _attempt(client, goal)
    foreign = _attempt(client, goal, device="device-b")
    assert foreign["status"] == "target_not_found"
    assert foreign["discovery"] is None
    assert foreign["target"] is None
    assert _attempt(client, goal) == completed


def test_replay_rejects_same_request_id_with_a_different_pair(world_goal):
    srv, client, goal = world_goal
    completed = _attempt(client, goal)
    mismatch = _attempt(client, goal, a="air", b="water")
    assert mismatch["status"] == "request_mismatch"
    assert mismatch["discovery"] is None
    assert mismatch["ether_charged"] == 0
    assert _attempt(client, goal) == completed
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_attempts").fetchone()[0] == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM device_grants WHERE device_id = 'device-a' "
            "AND ((kind = 'element' AND ref = 'steam') OR (kind = 'recipe' AND ref = 'fire|water'))"
        ).fetchone()[0] == 2


def test_next_slot_is_counted_from_completion_not_issuance(world_goal, monkeypatch):
    srv, client, goal = world_goal
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 23))
    done = _attempt(client, goal)
    waiting = _target(client)
    assert waiting["status"] == "waiting_next_slot"
    assert waiting["target"]["id"] == goal["id"]
    assert waiting["target"]["status"] == "completed"
    assert waiting["target"]["next_eligible_week"] == "2026-W49"

    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 30))
    fresh = _target(client)["target"]
    assert fresh["id"] != goal["id"]
    assert fresh["cycle_week"] == "2026-W49"
    assert _attempt(client, goal) == done
    stale = _attempt(client, goal, request_id="old-target-new-attempt")
    assert stale["status"] == "target_stale"
    assert _target(client)["target"]["attempts"] == 0


def test_world_goal_obtained_by_another_path_waits_without_completion(world_goal):
    srv, client, goal = world_goal
    with closing(srv.get_db()) as conn, conn:
        srv._grant_recipe(conn, "device-a", "fire|water", "fire", "water", "steam", "sync")
    state = _target(client)
    assert state["status"] == "waiting_next_slot"
    assert state["target"]["status"] == "waiting_next_slot"
    assert state["target"]["id"] == goal["id"]
    assert state["target"]["successful_steps"] == state["target"]["spent_ether"] == 0


def test_target_already_owned_reports_no_acquisition_and_waits(world_goal):
    srv, client, goal = world_goal
    with closing(srv.get_db()) as conn, conn:
        srv._grant_recipe(conn, "device-a", "fire|water", "fire", "water", "steam", "sync")
    result = _attempt(client, goal)
    assert result["status"] == "target_already_owned"
    assert result["acquired"] is False
    assert result["discovery"] is None
    assert result["ether_charged"] == 0
    assert result["target"]["status"] == "waiting_next_slot"
    assert _attempt(client, goal) == result


def test_pending_replay_releases_write_lock_while_waiting(world_goal, monkeypatch):
    srv, client, goal = world_goal
    with closing(srv.get_db()) as conn, conn:
        srv._grant_recipe(conn, "device-a", "fire|water", "fire", "water", "steam", "sync")
    monkeypatch.setattr(srv, "LOCK_TTL", 0.5)
    original_owns = srv._personal_device_owns
    ownership_checks = 0

    def inject_claim(conn, device_id, slug):
        nonlocal ownership_checks
        ownership_checks += 1
        if ownership_checks == 3:
            with closing(srv.get_db()) as claim_conn, claim_conn:
                claim_conn.execute(
                    "INSERT INTO personal_experiment_attempts "
                    "(target_id, device_id, request_id, pair_key, status, response_json, "
                    "claim_token, claimed_at, created_at) VALUES (?, ?, ?, ?, 'processing', '', ?, ?, ?)",
                    (goal["id"], "device-a", "pending-world", "fire|water", "owner", time.time(), srv._now_iso()),
                )
        return original_owns(conn, device_id, slug)

    monkeypatch.setattr(srv, "_personal_device_owns", inject_claim)
    original_replay = srv._personal_attempt_replay
    replay_locked = Event()

    def observe_replay(conn, *args, **kwargs):
        if conn.in_transaction:
            replay_locked.set()
        return original_replay(conn, *args, **kwargs)

    monkeypatch.setattr(srv, "_personal_attempt_replay", observe_replay)

    def finalize():
        assert replay_locked.wait(2)
        with closing(srv.get_db()) as conn, conn:
            target = conn.execute(
                "SELECT * FROM personal_experiment_targets WHERE id = ?", (goal["id"],)
            ).fetchone()
            response = srv._personal_attempt_response(
                target_id=goal["id"], request_id="pending-world", pair_key="fire|water",
                status="known", message="Finalized by the claim owner.",
                target=srv._personal_target_snapshot(target),
            )
            conn.execute(
                "UPDATE personal_experiment_attempts SET status = 'known', response_json = ?, "
                "claim_token = NULL, claimed_at = NULL WHERE request_id = 'pending-world'",
                (json.dumps(srv._personal_response_payload(response), ensure_ascii=False),),
            )

    with ThreadPoolExecutor(max_workers=1) as pool:
        pending = pool.submit(finalize)
        result = _attempt(client, goal, request_id="pending-world")
        pending.result(timeout=2)

    assert result["status"] == "known"
    assert result["target"]["status"] == "active"
    assert result["target"]["attempts"] == 0


def test_concurrent_world_attempts_can_only_complete_once(world_goal):
    srv, client, goal = world_goal
    barrier = Barrier(2, timeout=5)

    def submit(request_id):
        barrier.wait()
        return _attempt(client, goal, request_id=request_id)

    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(submit, ("parallel-1", "parallel-2")))
    assert sorted(r["status"] for r in replies) == ["known", "target_stale"]
    assert sum(r["ether_charged"] for r in replies) == 12
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_attempts").fetchone()[0] == 1


class _TargetEvaluator:
    provider = "mock"

    def __init__(self, outcomes=None):
        self.outcomes = outcomes or {}

    def available(self):
        return True

    def generate_personal_target(self, seed):
        return {"name": "Рассвет", "hint": "Найди образ света, который приходит после тьмы."}

    def evaluate_personal_target(self, target_name, a_name, b_name, known_context=""):
        key = tuple(sorted((a_name, b_name)))
        outcome = self.outcomes.get(key, {"outcome": "invalid"})
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome


class _PausedTargetEvaluator(_TargetEvaluator):
    provider = "openrouter"

    def __init__(self, outcomes):
        super().__init__(outcomes)
        self.calls = 0
        self.lock = Lock()

    def evaluate_personal_target(self, target_name, a_name, b_name, known_context=""):
        with self.lock:
            self.calls += 1
        Event().wait(0.25)
        return super().evaluate_personal_target(target_name, a_name, b_name, known_context)


class _SequenceTargetEvaluator(_TargetEvaluator):
    def __init__(self, names):
        super().__init__()
        self.names = iter(names)
        self.calls = 0

    def generate_personal_target(self, seed):
        self.calls += 1
        return {"name": next(self.names), "hint": "Найди новый образ."}


@pytest.fixture
def llm_goal(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _TargetEvaluator()
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    goal = _target(client, "boundary-21")["target"]
    assert goal["kind"] == "llm"
    return srv, client, goal, llm


def test_llm_goal_retries_world_name_conflict_without_changing_bucket(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _SequenceTargetEvaluator(["Пар", "Рассвет"])
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    goal = _target(client, "boundary-21")["target"]

    assert goal["kind"] == "llm"
    assert goal["name"] == "Рассвет"
    assert llm.calls == 2


def test_llm_goal_retries_transient_generation_errors_without_changing_bucket(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _TargetEvaluator()
    calls = []

    def generate(seed):
        calls.append(seed)
        if len(calls) < 3:
            raise srv.LLMError("temporary failure")
        return {"name": "Рассвет", "hint": "Найди образ света после тьмы."}

    llm.generate_personal_target = generate
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    goal = _target(client, "boundary-21")["target"]

    assert goal["kind"] == "llm"
    assert goal["name"] == "Рассвет"
    assert len(calls) == 3
    assert len(set(calls)) == 1


def test_llm_goal_conflict_retries_are_bounded_and_do_not_claim_slot(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _SequenceTargetEvaluator(["Пар"] * 5)
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    blocked = _target(client, "boundary-21")

    assert (blocked["ok"], blocked["status"], blocked["target"]) == (False, "target_unavailable", None)
    assert llm.calls == 3
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 0


def test_llm_goal_rejects_invalid_name_at_server_boundary(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _SequenceTargetEvaluator(["РассветA"] * 5)
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    blocked = _target(client, "boundary-21")

    assert (blocked["ok"], blocked["status"], blocked["target"]) == (False, "target_unavailable", None)
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_targets").fetchone()[0] == 0


def test_llm_goal_rejects_internal_seed_echo_at_server_boundary(quest, monkeypatch):
    srv, client = quest
    monkeypatch.setattr(srv, "_today_date", lambda: date(2026, 11, 22))
    llm = _TargetEvaluator()
    calls = []

    def generate(seed):
        calls.append(seed)
        if len(calls) == 1:
            return {"name": "Рассвет", "hint": f"Внутренний seed: {seed}."}
        return {"name": "Рассвет", "hint": "Найди свет после тьмы."}

    llm.generate_personal_target = generate
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    _grant_catalog_except(srv, "__no_such_slug__", device="boundary-21")

    goal = _target(client, "boundary-21")["target"]

    assert goal["hint"] == "Найди свет после тьмы."
    assert len(calls) == 2
    assert calls[0] == calls[1]
    assert calls[0] not in goal["hint"]


def test_llm_intermediate_materializes_new_step_without_completion(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[('Огонь', 'Огонь')] = {
        "outcome": "intermediate", "name": "Пламя", "relation": "metaphor",
        "description": "Два огня складываются в единый образ пламени.",
    }
    result = _attempt(client, goal, a="fire", b="fire", device="boundary-21", request_id="llm-intermediate")
    assert result["status"] == "created"
    assert result["acquired"] is True
    assert result["discovery"]["name"] == "Пламя"
    assert result["discovery"]["reused"] is False
    assert result["target"]["status"] == "active"
    assert result["target"]["successful_steps"] == 1
    assert result["target"]["spent_ether"] == result["ether_charged"] == 12
    assert result["target"]["slug"] == ""


def test_llm_raw_join_is_rejected_by_production_semantic_guardrails(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[("Огонь", "Огонь")] = {
        "outcome": "intermediate", "name": "ОгоньОгонь", "relation": "group",
        "description": "Механическая склейка двух входов.",
    }

    result = _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="llm-raw-join",
    )

    assert result["status"] == "invalid"
    assert result["acquired"] is False
    assert result["discovery"] is None
    assert result["ether_charged"] == 0
    assert result["target"]["successful_steps"] == 0
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM elements WHERE name = 'ОгоньОгонь'").fetchone()[0] == 0


def test_llm_reused_and_known_intermediates_do_not_complete_fresh_target(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[("Огонь", "Огонь")] = {
        "outcome": "intermediate", "name": "Пар", "relation": "physical",
        "description": "Два огня образуют пар.",
    }

    reused = _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="llm-reused",
    )
    assert reused["status"] == "created"
    assert reused["discovery"]["reused"] is True
    assert reused["acquired"] is True
    assert reused["ether_charged"] == 12
    assert reused["target"]["status"] == "active"
    assert _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="llm-reused",
    ) == reused

    known = _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="llm-known-intermediate",
    )
    assert known["status"] == "known"
    assert known["acquired"] is False
    assert known["ether_charged"] == 0
    assert known["target"]["status"] == "active"
    assert known["target"]["successful_steps"] == 1
    assert known["target"]["spent_ether"] == 12


def test_llm_exact_fresh_target_completes_only_on_target_outcome(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[('Земля', 'Земля')] = {
        "outcome": "target", "name": "Рассвет", "relation": "poetic_ironic",
        "description": "Две земли открывают образ нового рассвета.",
    }
    result = _attempt(client, goal, a="earth", b="earth", device="boundary-21", request_id="llm-target")
    assert result["status"] == "created"
    assert result["acquired"] is True
    assert result["discovery"]["name"] == "Рассвет"
    assert result["discovery"]["reused"] is False
    assert result["target"]["status"] == "completed"
    assert result["target"]["completed"] is True
    assert result["target"]["successful_steps"] == 1
    assert result["target"]["spent_ether"] == result["ether_charged"] == 12


def test_llm_target_outcome_with_different_name_cannot_materialize_or_complete(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[("Земля", "Земля")] = {
        "outcome": "target", "name": "Затмение", "relation": "metaphor",
        "description": "Две земли образуют образ затмения.",
    }

    result = _attempt(
        client, goal, a="earth", b="earth", device="boundary-21",
        request_id="llm-mismatched-target",
    )

    assert result["status"] == "target_conflict"
    assert result["acquired"] is False
    assert result["discovery"] is None
    assert result["ether_charged"] == 0
    assert result["target"]["status"] == "active"
    assert result["target"]["successful_steps"] == 0
    assert result["target"]["spent_ether"] == 0
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM elements WHERE name = 'Рассвет'").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM elements WHERE name = 'Затмение'").fetchone()[0] == 0
        assert conn.execute(
            "SELECT COUNT(*) FROM device_grants WHERE device_id = 'boundary-21'"
        ).fetchone()[0] == 0


def test_claim_ttl_covers_two_transport_posts_per_model(monkeypatch):
    import server as srv

    monkeypatch.delenv("LOCK_TTL_SEC", raising=False)
    monkeypatch.setenv("LLM_TIMEOUT", "30")
    monkeypatch.setattr(srv.gen_llm, "MAX_ATTEMPTS", 3)

    transport_window = 2 * srv.gen_llm.MAX_ATTEMPTS * 30.0

    assert srv._lock_ttl_seconds() >= transport_window * srv.LOCK_TTL_MARGIN


def test_concurrent_same_llm_request_replays_the_first_commit(llm_goal, monkeypatch):
    srv, client, goal, _llm = llm_goal
    barrier = Barrier(2, timeout=5)
    llm = _PausedTargetEvaluator({
        ("Земля", "Земля"): {
            "outcome": "target", "name": "Рассвет", "relation": "metaphor",
            "description": "Две земли открывают образ нового рассвета.",
        },
    })
    llm.provider = "mock"
    monkeypatch.setattr(srv, "get_llm", lambda: llm)

    def submit(_index):
        barrier.wait()
        return _attempt(
            client, goal, a="earth", b="earth", device="boundary-21",
            request_id="same-llm-request",
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(submit, range(2)))

    assert replies[0] == replies[1]
    assert replies[0]["status"] == "created"
    assert llm.calls == 1
    assert replies[0]["target"]["status"] == "completed"
    assert replies[0]["target"]["attempts"] == 1
    assert replies[0]["target"]["spent_ether"] == 12
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM personal_experiment_attempts").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM elements WHERE name = 'Рассвет'").fetchone()[0] == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM device_grants WHERE device_id = 'boundary-21' "
            "AND kind = 'element' AND ref = ?",
            (replies[0]["discovery"]["slug"],),
        ).fetchone()[0] == 1


def test_concurrent_same_external_llm_request_calls_provider_and_reserves_once(llm_goal, monkeypatch):
    srv, client, goal, _llm = llm_goal
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 2)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 2)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    llm = _PausedTargetEvaluator({
        ("Земля", "Земля"): {
            "outcome": "target", "name": "Рассвет", "relation": "metaphor",
            "description": "Две земли открывают образ нового рассвета.",
        },
    })
    monkeypatch.setattr(srv, "get_llm", lambda: llm)
    barrier = Barrier(2, timeout=5)

    def submit(_index):
        barrier.wait()
        return _attempt(
            client, goal, a="earth", b="earth", device="boundary-21",
            request_id="same-external-request",
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(submit, range(2)))

    assert replies[0] == replies[1]
    assert replies[0]["status"] == "created"
    assert llm.calls == 1
    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = 'boundary-21'"
        ).fetchone()[0] == 1
        assert conn.execute("SELECT attempts FROM experiment_global_limits LIMIT 1").fetchone()[0] == 1


def test_stale_llm_claim_is_reclaimed_and_finalized_once(llm_goal, monkeypatch):
    srv, client, goal, llm = llm_goal
    llm.outcomes[("Земля", "Земля")] = {
        "outcome": "target", "name": "Рассвет", "relation": "metaphor",
        "description": "Две земли открывают образ нового рассвета.",
    }
    monkeypatch.setattr(srv, "LOCK_TTL", 0.0)
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO personal_experiment_attempts "
            "(target_id, device_id, request_id, pair_key, status, response_json, "
            "claim_token, claimed_at, created_at) "
            "VALUES (?, 'boundary-21', 'stale-claim', 'earth|earth', 'processing', '', "
            "'abandoned-token', 0, ?)",
            (goal["id"], srv._now_iso()),
        )

    try:
        result = _attempt(
            client, goal, a="earth", b="earth", device="boundary-21",
            request_id="stale-claim",
        )
    except json.JSONDecodeError:
        pytest.fail("processing claim was deserialized as a final response")

    assert result["status"] == "created"
    assert result["target"]["attempts"] == 1
    with closing(srv.get_db()) as conn:
        row = conn.execute(
            "SELECT status, claim_token, claimed_at FROM personal_experiment_attempts "
            "WHERE target_id = ? AND request_id = 'stale-claim'",
            (goal["id"],),
        ).fetchone()
        assert (row["status"], row["claim_token"], row["claimed_at"]) == ("created", None, None)


def test_llm_claim_is_visible_during_evaluation_and_removed_after_exception(llm_goal):
    srv, client, goal, llm = llm_goal
    observed = []

    def fail(target_name, a_name, b_name, known_context=""):
        with closing(srv.get_db()) as conn:
            row = conn.execute(
                "SELECT status, claim_token FROM personal_experiment_attempts "
                "WHERE target_id = ? AND request_id = 'retry-after-exception'",
                (goal["id"],),
            ).fetchone()
            observed.append(dict(row) if row is not None else None)
        raise RuntimeError("evaluator crashed")

    llm.evaluate_personal_target = fail
    with pytest.raises(RuntimeError, match="evaluator crashed"):
        _attempt(
            client, goal, a="earth", b="earth", device="boundary-21",
            request_id="retry-after-exception",
        )
    assert observed and observed[0] is not None
    assert observed[0]["status"] == "processing"
    assert observed[0]["claim_token"]
    with closing(srv.get_db()) as conn:
        assert conn.execute(
            "SELECT COUNT(*) FROM personal_experiment_attempts "
            "WHERE target_id = ? AND request_id = 'retry-after-exception'",
            (goal["id"],),
        ).fetchone()[0] == 0

    llm.outcomes[("Земля", "Земля")] = {
        "outcome": "target", "name": "Рассвет", "relation": "metaphor",
        "description": "Две земли открывают образ нового рассвета.",
    }
    del llm.evaluate_personal_target
    retried = _attempt(
        client, goal, a="earth", b="earth", device="boundary-21",
        request_id="retry-after-exception",
    )
    assert retried["status"] == "created"
    assert retried["target"]["attempts"] == 1


def test_llm_invalid_unavailable_and_malformed_do_not_charge_or_change_graph(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[('Вода', 'Вода')] = {"outcome": "invalid"}
    llm.outcomes[('Воздух', 'Воздух')] = srv.LLMError("offline")
    llm.outcomes[('Воздух', 'Земля')] = {"outcome": "intermediate", "name": "сломано"}

    invalid = _attempt(client, goal, a="water", b="water", device="boundary-21", request_id="llm-invalid")
    unavailable = _attempt(client, goal, a="air", b="air", device="boundary-21", request_id="llm-unavailable")
    malformed = _attempt(client, goal, a="air", b="earth", device="boundary-21", request_id="llm-malformed")

    assert invalid["status"] == "invalid"
    assert unavailable["status"] == "unavailable"
    assert malformed["status"] == "invalid"
    assert all(result["ether_charged"] == 0 for result in (invalid, unavailable, malformed))
    assert all(result["target"]["successful_steps"] == 0 for result in (invalid, unavailable, malformed))
    with closing(srv.get_db()) as conn:
        assert conn.execute("SELECT COUNT(*) FROM elements WHERE name = 'сломано'").fetchone()[0] == 0


def test_llm_malformed_result_refunds_external_generation_reservation(llm_goal, monkeypatch):
    srv, client, goal, llm = llm_goal
    llm.provider = "openrouter"
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 5)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 5)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    llm.outcomes[("Вода", "Вода")] = {"outcome": "intermediate", "name": "сломано"}

    result = _attempt(
        client, goal, a="water", b="water", device="boundary-21",
        request_id="malformed-refund",
    )

    assert result["status"] == "invalid"
    assert result["ether_charged"] == 0
    with closing(srv.get_db()) as conn:
        device_attempts = conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = ?",
            ("boundary-21",),
        ).fetchone()
        global_attempts = conn.execute(
            "SELECT attempts FROM experiment_global_limits LIMIT 1"
        ).fetchone()
        assert (device_attempts[0] if device_attempts else 0) == 0
        assert (global_attempts[0] if global_attempts else 0) == 0


def test_llm_evaluator_exception_refunds_external_generation_reservation(llm_goal, monkeypatch):
    srv, client, goal, llm = llm_goal
    llm.provider = "openrouter"
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 1)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    llm.outcomes[("Земля", "Земля")] = RuntimeError("evaluator crashed")

    with pytest.raises(RuntimeError, match="evaluator crashed"):
        _attempt(
            client, goal, a="earth", b="earth", device="boundary-21",
            request_id="exception-refund",
        )

    with closing(srv.get_db()) as conn:
        device_attempts = conn.execute(
            "SELECT attempts FROM experiment_limits WHERE device_id = ?",
            ("boundary-21",),
        ).fetchone()
        global_attempts = conn.execute(
            "SELECT attempts FROM experiment_global_limits LIMIT 1"
        ).fetchone()
        assert (device_attempts[0] if device_attempts else 0) == 0
        assert (global_attempts[0] if global_attempts else 0) == 0

    llm.outcomes[("Земля", "Земля")] = {
        "outcome": "target", "name": "Рассвет", "relation": "metaphor",
        "description": "Две земли открывают образ нового рассвета.",
    }
    retried = _attempt(
        client, goal, a="earth", b="earth", device="boundary-21",
        request_id="exception-refund",
    )
    assert retried["status"] == "created"
    assert retried["target"]["attempts"] == 1


def test_llm_rate_limit_replays_after_quota_reset(llm_goal, monkeypatch):
    srv, client, goal, llm = llm_goal
    llm.provider = "openrouter"
    llm.outcomes[("Земля", "Земля")] = {
        "outcome": "target", "name": "Рассвет", "relation": "metaphor",
        "description": "Две земли открывают образ нового рассвета.",
    }
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 1)
    monkeypatch.setattr(srv, "EXPERIMENT_GLOBAL_DAILY_LIMIT", 5)
    monkeypatch.setattr(srv, "EXPERIMENT_COOLDOWN_SEC", 0.0)
    with closing(srv.get_db()) as conn, conn:
        conn.execute(
            "INSERT INTO experiment_limits (day, device_id, attempts, last_at) "
            "VALUES (?, 'boundary-21', 1, 0)",
            (srv._today(),),
        )

    limited = _attempt(
        client, goal, a="earth", b="earth", device="boundary-21",
        request_id="limited-request",
    )
    assert limited["status"] == "rate_limited"
    monkeypatch.setattr(srv, "EXPERIMENT_DAILY_LIMIT", 5)

    assert _attempt(
        client, goal, a="earth", b="earth", device="boundary-21",
        request_id="limited-request",
    ) == limited
    assert _target(client, "boundary-21")["target"]["status"] == "active"


def test_llm_materialization_uses_canonical_player_nick(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[("Огонь", "Огонь")] = {
        "outcome": "intermediate", "name": "Пламя", "relation": "physical",
        "description": "Два огня усиливают единое пламя.",
    }

    result = _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="canonical-author", nick="Подменён",
    )

    assert result["discovery"]["author"] == "Аня"
    with closing(srv.get_db()) as conn:
        element = conn.execute(
            "SELECT author FROM elements WHERE slug = ?", (result["discovery"]["slug"],)
        ).fetchone()
        recipe = conn.execute(
            "SELECT discoverer FROM recipes WHERE pair_key = 'fire|fire'"
        ).fetchone()
        assert element["author"] == "Аня"
        assert recipe["discoverer"] == "Аня"


def test_llm_response_does_not_disclose_evaluator_explanation(llm_goal):
    import json

    srv, client, goal, llm = llm_goal
    secret = "Секретный внутренний вывод evaluator"
    llm.outcomes[("Огонь", "Огонь")] = {
        "outcome": "intermediate", "name": "Пламя", "relation": "metaphor",
        "description": secret,
    }

    result = _attempt(
        client, goal, a="fire", b="fire", device="boundary-21",
        request_id="private-evaluation",
    )

    assert secret not in json.dumps(result, ensure_ascii=False)
    assert result["discovery"]["d"]
    with closing(srv.get_db()) as conn:
        element = conn.execute(
            "SELECT d FROM elements WHERE slug = ?", (result["discovery"]["slug"],)
        ).fetchone()
        journal = conn.execute(
            "SELECT response_json FROM personal_experiment_attempts "
            "WHERE target_id = ? AND request_id = 'private-evaluation'",
            (goal["id"],),
        ).fetchone()
        assert secret not in element["d"]
        assert secret not in journal["response_json"]


def test_llm_known_result_does_not_complete_fresh_target(llm_goal):
    srv, client, goal, llm = llm_goal
    llm.outcomes[('Вода', 'Огонь')] = {
        "outcome": "target", "name": "Рассвет", "relation": "metaphor",
        "description": "Жар и влага создают образ рассвета.",
    }
    result = _attempt(client, goal, a="fire", b="water", device="boundary-21", request_id="llm-known")
    assert result["status"] == "target_conflict"
    assert result["target"]["status"] == "active"
    assert result["target"]["successful_steps"] == 0
    assert result["ether_charged"] == 0


def test_target_bucket_is_stable_for_device_week_and_sequence():
    from personal_experiment import target_bucket

    first = target_bucket("device-a", "2026-W48", 1)
    second = target_bucket("device-a", "2026-W48", 1)

    assert first == second
    assert 0 <= first < 100


def test_world_bucket_is_replaced_with_llm_only_when_frontier_is_empty():
    from personal_experiment import choose_target_kind, target_bucket

    kinds = [
        choose_target_kind("device-%d" % index, "2026-W48", 1, True)
        for index in range(10000)
    ]
    repeated = [
        choose_target_kind("device-%d" % index, "2026-W48", 1, True)
        for index in range(10000)
    ]

    assert kinds == repeated
    assert kinds.count("world") == sum(
        target_bucket("device-%d" % index, "2026-W48", 1) < 80
        for index in range(10000)
    )
    assert 7800 <= kinds.count("world") <= 8200
    assert all(
        choose_target_kind("device-%d" % index, "2026-W48", 1, False) == "llm"
        for index in range(1000)
    )


def test_init_db_creates_personal_target_tables_and_snapshot_shape(tmp_path, monkeypatch):
    import server as srv

    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "target.db"))
    srv.init_db()
    conn = srv.get_db()
    names = {
        row["name"]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
    }
    assert "personal_experiment_targets" in names
    assert "personal_experiment_attempts" in names
    conn.close()


def test_target_name_normalization_matches_element_deduplication():
    from personal_experiment import normalize_target_name

    assert normalize_target_name("  Ёлка   Звёздная ") == "елка звездная"


def test_target_snapshot_excludes_hidden_target_fields():
    from personal_experiment import target_snapshot

    snapshot = target_snapshot({
        "id": "target-1",
        "kind": "llm",
        "target_slug": "",
        "target_name": "Рассвет",
        "target_hint": "Найди свет после тьмы.",
        "status": "active",
        "cycle_week": "2026-W48",
        "attempts": 2,
        "successful_steps": 1,
        "spent_ether": 12,
        "target_name_norm": "рассвет",
        "source_pair": "fire|night",
        "target_seed": "secret",
    })

    assert snapshot["name"] == "Рассвет"
    assert "target_name_norm" not in snapshot
    assert "source_pair" not in snapshot
    assert "target_seed" not in snapshot
