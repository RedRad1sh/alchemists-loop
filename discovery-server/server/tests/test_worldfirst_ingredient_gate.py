"""Task 5: route-level gate — world-first требует генеративный ингредиент в grants.

Анти-чит: чтобы сварить пару с НЕ-базовым (генеративным) входом, этот вход обязан
лежать в device_grants игрока (kind='element') — т.е. он легитимно получен варкой
(рецепт грантится через _grant_recipe, в т.ч. recovery-путём). Выдуманный игроком
slug-«ингредиент» отбрасывается ДО входа в транзакцию: lock/generation не
запускаются, квота LLM не тратится.

Мутации-красные:
- убрать гейт → обе варки проходят в транзакцию, test_generated... покраснеет.
- гейт на базовых входах → test_base_ingredients_pass покраснеет.
- гейт ПОСЛЕ _try_acquire_pair_lock → транзакция затронута (нарушение контракта).
"""
import os
import sys

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "gate.db"))
    return srv


def _materialize_element(srv, slug):
    conn = srv.get_db()
    try:
        conn.execute(
            "INSERT INTO elements (slug, name, color, layer, category) VALUES (?,?,?,?,?)",
            (slug, slug.capitalize(), "#101010", 4, "misc"),
        )
        conn.commit()
    finally:
        conn.close()


def test_generated_ingredient_not_in_grants_is_rejected_before_transaction(tmp_path, monkeypatch):
    """Реальный materialized генеративный элемент, не гранчёный device'у → гейт до лока."""
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:  # startup → init_db
        _materialize_element(srv, "shadowmire")  # существует, но res-игроку не выдан
        r = client.post("/api/discover", json={
            "a": "shadowmire", "b": "fire",
            "nick": "n", "device_id": "devForg", "experiment": True,
        })
    assert r.status_code == 200
    body = r.json()
    assert body.get("detail") == "ingredient_not_granted"
    assert body["ok"] is False


def test_base_ingredients_pass_gate(tmp_path, monkeypatch):
    srv = _srv(tmp_path, monkeypatch)

    class FakeLLM:
        def available(self):
            return True

        def generate(self, *a, **k):
            return {"combinable": True, "name": "Что-то"}

    monkeypatch.setattr(srv, "get_llm", lambda: FakeLLM())
    with TestClient(srv.app) as client:
        # базовые входы не требуют grants — гейт их пропускает в транзакцию как обычно
        r = client.post("/api/discover", json={
            "a": "fire", "b": "water", "nick": "n", "device_id": "devOK", "experiment": True,
        })
    assert r.json().get("detail") != "ingredient_not_granted"


def test_author_can_chain_brew_from_own_world_first_without_sync(tmp_path, monkeypatch):
    """Review #4: автор element (recipes.discoverer_device) обязан варить из своего
    world-first СРАЗУ, не дожидаясь sync-гранта (спека §"Граница приёма гранта"
    включает «собственный /discover device»). Мутация-красная: убрать
    `_element_authored_by` из гейта → автору вернётся ingredient_not_granted (легитимный
    chain-world-first блокируется до ближайшего sync, до 60с)."""
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:  # startup → init_db
        conn = srv.get_db()
        try:
            eid = conn.execute(
                "INSERT INTO elements (slug, name, color, layer, category) VALUES (?,?,?,?,?)",
                ("authorbio", "Автор-био", "#101010", 4, "misc"),
            ).lastrowid
            conn.execute(
                "INSERT INTO recipes (pair_key, a, b, out_id, discoverer, discoverer_device, linked) "
                "VALUES ('a|authorbio', 'a', 'authorbio', ?, 'Автор', 'devAuthor', 0)",
                (eid,),
            )
            conn.commit()
        finally:
            conn.close()
        r = client.post("/api/discover", json={
            "a": "authorbio", "b": "gold",  # gold не materialized → ниже fog/not_combinable
            "nick": "n", "device_id": "devAuthor", "experiment": True,
        })
    assert r.json().get("detail") != "ingredient_not_granted"


def test_foreign_world_first_still_gated_for_non_author(tmp_path, monkeypatch):
    """Fix #4 не открывает дыру: element, авторизованный ДРУГИМ device, по-прежнему
    гейтится для чужака (иначе review #4-фикс ослабил бы анти-чит)."""
    srv = _srv(tmp_path, monkeypatch)
    with TestClient(srv.app) as client:
        conn = srv.get_db()
        try:
            eid = conn.execute(
                "INSERT INTO elements (slug, name, color, layer, category) VALUES (?,?,?,?,?)",
                ("authorbio", "Автор-био", "#101010", 4, "misc"),
            ).lastrowid
            conn.execute(
                "INSERT INTO recipes (pair_key, a, b, out_id, discoverer, discoverer_device, linked) "
                "VALUES ('a|authorbio', 'a', 'authorbio', ?, 'Автор', 'devAuthor', 0)",
                (eid,),
            )
            conn.commit()
        finally:
            conn.close()
        r = client.post("/api/discover", json={
            "a": "authorbio", "b": "gold", "nick": "n", "device_id": "devOther", "experiment": True,
        })
    assert r.status_code == 200
    assert r.json().get("detail") == "ingredient_not_granted"
    assert r.json()["ok"] is False
    """Легитимный генеративный вход (есть kind='element'-грант) — гейт пропускает."""
    srv = _srv(tmp_path, monkeypatch)

    class FakeLLM:
        def available(self):
            return True

        def generate(self, *a, **k):
            return {"combinable": True, "name": "Дистиллят"}

    monkeypatch.setattr(srv, "get_llm", lambda: FakeLLM())
    with TestClient(srv.app) as client:  # startup → init_db создаёт таблицы
        # легитимный путь: игрок получил shadowmire варкой → element-грант в журнале
        conn = srv.get_db()
        try:
            conn.execute(
                "INSERT INTO elements (slug, name, color, layer, category) VALUES (?,?,?,?,?)",
                ("shadowmire", "Тень-топь", "#101010", 4, "misc"),
            )
            conn.execute(
                "INSERT INTO device_grants (device_id, kind, ref, source, granted_at) "
                "VALUES (?, 'element', 'shadowmire', 'local_learn', '2026-01-01T00:00:00')",
                ("devGood",),
            )
            conn.commit()
        finally:
            conn.close()
        r = client.post("/api/discover", json={
            "a": "shadowmire", "b": "water", "nick": "n", "device_id": "devGood", "experiment": True,
        })
    assert r.json().get("detail") != "ingredient_not_granted"

