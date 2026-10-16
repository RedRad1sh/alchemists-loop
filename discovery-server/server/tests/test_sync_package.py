"""Task 2: POST /api/sync/package — приём Part B-грантов + отдача device_grants.

Мутации-красные:
- убрать вызов _grant_recipe → accepted=0, grants пустые.
- принимать выдуманные пары без гейта → rejected=0 (дыра «заявил все скрытые пары»).
"""
import os
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "syncpkg.db"))
    return srv


def test_sync_package_stores_corroborated_and_rejects_forgery(tmp_path, monkeypatch):
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        r = client.post("/api/sync/package", json={
            "device_id": "dev9", "schema_version": 4, "client_rev": 1,
            "anchor_accrual_ts": 1000.0,
            "part_b": {"recipes": [
                {"pair_key": "fire|water", "a": "fire", "b": "water", "out": "steam"},
                {"pair_key": "ghost|x", "a": "ghost", "b": "x", "out": "y"},  # выдумана
            ], "elements": []},
        })
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["accepted"] == 1 and body["rejected"] == 1
    refs = {g["ref"] for g in body["grants"]}
    assert "fire|water" in refs and "ghost|x" not in refs
    # server_seen_ts — wall-clock сервера (float), для wall-clock-аккумуляции Task 4
    assert isinstance(body["server_seen_ts"], float)


def test_sync_package_is_idempotent_on_repeat(tmp_path, monkeypatch):
    srv = _srv(tmp_path, monkeypatch)
    payload = {
        "device_id": "devI", "schema_version": 4, "client_rev": 1,
        "anchor_accrual_ts": 1000.0,
        "part_b": {"recipes": [
            {"pair_key": "fire|water", "a": "fire", "b": "water", "out": "steam"},
        ], "elements": []},
    }
    with TestClient(srv.app) as client:
        r1 = client.post("/api/sync/package", json=payload).json()
        r2 = client.post("/api/sync/package", json=payload).json()
    assert r1["accepted"] == 1
    # второй синк той же пары — дубликат (accepted=0, rejected=0), grants не дублируются
    assert r2["accepted"] == 0 and r2["rejected"] == 0
    recipe_grants = [g for g in r2["grants"] if g["ref"] == "fire|water"]
    assert len(recipe_grants) == 1


def test_sync_package_grant_content_is_authoritative_not_client_forged(tmp_path, monkeypatch):
    """Critical (review #1): контент гранта обязан браться из таблицы recipes, а не из
    заявления клиента. Иначе реальную корроборированную пару (fire|water) заявляют с
    поддельным out = чужой скрытый world-first slug → сервер пишет element-грант на
    выдуманный выход → гейт world-first (§28) открывается даром. Это ровно та дыра,
    ради которой закрыт весь feature. Мутация-красная: вернуть in-route `rec.out` в
    _grant_recipe вместо authoritative-чтения из recipes → 'fabricatedgold' появится
    в element-грантах → тест покраснеет (сегодня КРАСНЫЙ: grant пишет out из клиента)."""
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        body = client.post("/api/sync/package", json={
            "device_id": "devForge", "schema_version": 4, "client_rev": 1,
            "anchor_accrual_ts": 0.0,
            "part_b": {"recipes": [
                # пара реальная (базовый сид), но out подделан под чужой secret
                {"pair_key": "fire|water", "a": "fire", "b": "water", "out": "fabricatedgold"},
            ], "elements": []},
        }).json()
    recipe_grants = [g for g in body["grants"] if g["kind"] == "recipe" and g["ref"] == "fire|water"]
    assert len(recipe_grants) == 1
    # Поддельный out не попал ни в какой element-грант (авторитетен recipes.out).
    element_refs = {g["ref"] for g in body["grants"] if g["kind"] == "element"}
    assert "fabricatedgold" not in element_refs
    # ...и recipe-грант несёт настоящее определение из каталога, не клиентское.
    assert recipe_grants[0]["out"] != "fabricatedgold" and recipe_grants[0]["out"] != ""


def test_sync_package_rejects_oversized_payload(tmp_path, monkeypatch):
    """Important #5 (2GB/2CPU + SQLite variable limit): раздутый part_b отклоняется
    в валидации (422) ДО цикла грантов — сервер не крутит thousands of statements и
    не строит гигантский IN(...) для recovery. Мутация-красная: снять max_length →
    422 превращается в 200 (payload обработан целиком)."""
    srv = _srv(tmp_path, monkeypatch)
    huge = [{"pair_key": f"x{i}|y{i}", "a": f"x{i}", "b": f"y{i}", "out": f"z{i}"}
            for i in range(4097)]  # на 1 больше SyncPartB.recipes.max_length
    with TestClient(srv.app) as client:
        r = client.post("/api/sync/package", json={
            "device_id": "devFlood", "schema_version": 4, "client_rev": 1,
            "anchor_accrual_ts": 0.0, "part_b": {"recipes": huge, "elements": []},
        })
    assert r.status_code == 422


def test_sync_package_does_not_create_player(tmp_path, monkeypatch):
    """Синк — не дверь регистрации: unknown device не порождает строку players,
    но гранты знаний всё равно пишутся (это Part B-журнал, не аккаунт)."""
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        r = client.post("/api/sync/package", json={
            "device_id": "devGhost", "schema_version": 4, "client_rev": 1,
            "anchor_accrual_ts": 1000.0,
            "part_b": {"recipes": [
                {"pair_key": "earth|fire", "a": "earth", "b": "fire", "out": "stone"},
            ], "elements": []},
        }).json()
        me = client.get("/api/me", params={"device_id": "devGhost"}).json()
    assert r["accepted"] == 1
    # профиля-регистации нет → nick пустой (device не зарегистрирован синком)
    assert me.get("nick", "") == ""


def test_sync_package_contract_offline_inflation_not_trusted(tmp_path, monkeypatch):
    """Task 12 контракт: оффлайн-накрутка не двигает server-relevant слой.

    Игрок шлёт выдуманную нераскрытую пару + надутый оффлайн-банк. Сервер:
    - rejected≥1 и grants НЕ содержат выдуманную пару (Part B корроборация);
    - advisory accrual_ceiling (wall-clock elapsed×rate) на порядки меньше
      заявленного declared-банка — сервер не признает накрутку (Part C client-wins,
      но потолок честный)."""
    import time
    srv = _srv(tmp_path, monkeypatch)
    anchor = time.time() - 5.0  # 5 секунд честного elapsed → потолок ~5 при rate=1
    with TestClient(srv.app) as client:
        r = client.post("/api/sync/package", json={
            "device_id": "devCheat", "schema_version": 4, "client_rev": 1,
            "anchor_accrual_ts": anchor,
            "part_b": {"recipes": [
                {"pair_key": "fire|water", "a": "fire", "b": "water", "out": "steam"},
                {"pair_key": "cheat|hidden", "a": "cheat", "b": "hidden", "out": "gold"},
            ], "elements": []},
            "part_c": {"inventory_slugs": [], "accrual_declared": 1_000_000_000.0,
                       "accrual_rate_declared": 1.0},
        }).json()
    assert r["ok"] is True
    assert r["rejected"] >= 1
    refs = {g["ref"] for g in r["grants"]}
    assert "fire|water" in refs and "cheat|hidden" not in refs
    # Честный wall-clock-потолок (≈5) на порядки меньше накрученного банка (1e9).
    assert 0.0 < r["accrual_ceiling"] < 1_000_000.0
