"""Аркан Сигилов: каталог карт и его выдача.

Харнесс повторяет идиому test_house_visits.py: _srv поднимает модуль с
временной БД, _client зовёт init_db() и заворачивает app в TestClient БЕЗ
контекстного менеджера — startup-хук server.py трогать не нужно.
"""

import inspect
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

import server as srv  # noqa: E402


MINI_CATALOG = {
    "version": "0123456789abcdef",
    "generated_at": "2026-09-30T00:00:00Z",
    "sets": [
        {"id": "fire", "title": "Стихия Огня", "card_ids": ["spark", "coal"]},
        {"id": "water", "title": "Стихия Воды", "card_ids": ["ice", "mist"]},
        {"id": "air", "title": "Стихия Воздуха", "card_ids": ["cloud", "smoke"]},
        {"id": "earth", "title": "Стихия Земли", "card_ids": ["lava", "stone"]},
    ],
    "cards": [
        {
            "id": "spark", "set": "fire", "rarity": "common",
            "recipe": [{"item_id": "fire", "qty": 10}, {"item_id": "air", "qty": 12}],
            "ether_cost": 40, "process": "искры из воздуха", "stage": 1,
            "fallback_name": "Искра", "object_type": "object", "seed": 11,
        },
        {
            "id": "coal", "set": "fire", "rarity": "common",
            "recipe": [{"item_id": "fire", "qty": 14}, {"item_id": "stone", "qty": 9}],
            "ether_cost": 45, "process": "обугленное дерево", "stage": 2,
            "fallback_name": "Уголь", "object_type": "object", "seed": 12,
        },
        {
            "id": "ice", "set": "water", "rarity": "rare",
            "recipe": [{"item_id": "water", "qty": 30}, {"item_id": "air", "qty": 20}],
            "ether_cost": 160, "process": "застывшая вода", "stage": 2,
            "fallback_name": "Лёд", "object_type": "object", "seed": 33,
        },
        {
            "id": "mist", "set": "water", "rarity": "rare",
            "recipe": [{"item_id": "water", "qty": 24}, {"item_id": "steam", "qty": 18}],
            "ether_cost": 150, "process": "туман над водой", "stage": 2,
            "fallback_name": "Туман", "object_type": "abstraction", "seed": 34,
        },
        {
            "id": "cloud", "set": "air", "rarity": "epic",
            "recipe": [{"item_id": "steam", "qty": 60}, {"item_id": "air", "qty": 70}],
            "ether_cost": 380, "process": "сгущение пара", "stage": 3,
            "fallback_name": "Облако", "object_type": "object", "seed": 44,
        },
        {
            "id": "smoke", "set": "air", "rarity": "epic",
            "recipe": [{"item_id": "fire", "qty": 55}, {"item_id": "plant", "qty": 40}],
            "ether_cost": 360, "process": "горение травы", "stage": 3,
            "fallback_name": "Дым", "object_type": "abstraction", "seed": 45,
        },
        {
            "id": "lava", "set": "earth", "rarity": "legendary",
            "recipe": [
                {"item_id": "stone", "qty": 120}, {"item_id": "fire", "qty": 150},
                {"item_id": "metal", "qty": 90}, {"item_id": "earth", "qty": 200},
            ],
            "ether_cost": 900, "process": "расплав глубин", "stage": 5,
            "fallback_name": "Лава", "object_type": "abstraction", "seed": 22,
        },
        {
            "id": "stone", "set": "earth", "rarity": "common",
            "recipe": [{"item_id": "earth", "qty": 8}, {"item_id": "fire", "qty": 6}],
            "ether_cost": 35, "process": "спекшаяся глина", "stage": 1,
            "fallback_name": "Камень", "object_type": "object", "seed": 55,
        },
    ],
}

MINI_IDS = ["spark", "coal", "ice", "mist", "cloud", "smoke", "lava", "stone"]


def _srv(tmp_path, monkeypatch):
    monkeypatch.setenv("LLM_PROVIDER", "mock")
    srv.DB_PATH = str(tmp_path / "test.db")
    return srv


def _client(s):
    s.init_db()
    return TestClient(s.app)


def _mini(s, tmp_path, monkeypatch):
    """Подменить боевой каталог маленьким и вернуть готовый клиент."""
    path = tmp_path / "mini_catalog.json"
    path.write_text(json.dumps(MINI_CATALOG, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(s, "SIGIL_CATALOG_PATH", str(path))
    s._sigil_catalog_cache_clear()
    return _client(s)


class TestCatalog:
    def test_catalog_is_served(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.get("/api/sigil/catalog")
        assert r.status_code == 200
        body = r.json()
        assert body["ok"] is True
        assert body["error"] == ""
        assert body["version"] == "0123456789abcdef"
        assert [s["id"] for s in body["sets"]] == ["fire", "water", "air", "earth"]
        assert [c["id"] for c in body["cards"]] == MINI_IDS
        fire = next(s for s in body["sets"] if s["id"] == "fire")
        assert fire["title"] == "Стихия Огня"
        assert fire["card_ids"] == ["spark", "coal"]
        lava = next(c for c in body["cards"] if c["id"] == "lava")
        assert lava["rarity"] == "legendary"
        assert lava["ether_cost"] == 900
        assert len(lava["recipe"]) == 4
        assert lava["object_type"] == "abstraction"
        assert lava["seed"] == 22

    def test_missing_catalog_reports_error(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(s, "SIGIL_CATALOG_PATH", str(tmp_path / "nope.json"))
        s._sigil_catalog_cache_clear()
        r = _client(s).get("/api/sigil/catalog")
        assert r.status_code == 200
        assert r.json() == {
            "ok": False, "version": "", "sets": [], "cards": [],
            "error": "catalog_empty",
        }

    def test_broken_catalog_reports_error(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        path = tmp_path / "broken.json"
        path.write_text("{ not json", encoding="utf-8")
        monkeypatch.setattr(s, "SIGIL_CATALOG_PATH", str(path))
        s._sigil_catalog_cache_clear()
        r = _client(s).get("/api/sigil/catalog")
        assert r.json()["error"] == "catalog_empty"

    def test_real_catalog_is_loadable(self):
        data = srv._sigil_catalog()
        assert len(data["cards"]) == 100
        assert len(data["sets"]) == 4
        assert len(data["version"]) == 16
        assert int(data["version"], 16) >= 0
        assert set(data["by_id"]) == {c["id"] for c in data["cards"]}

    def test_catalog_is_cached_between_calls(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        client.get("/api/sigil/catalog")
        first = srv._sigil_catalog()["cards"]
        client.get("/api/sigil/catalog")
        # Тот же объект списка -> кэш по mtime сработал, повторного парсинга нет.
        assert srv._sigil_catalog()["cards"] is first

    def test_catalog_handler_is_sync(self):
        # T29: хендлеры, трогающие БД/диск, обязаны быть sync def.
        assert inspect.iscoroutinefunction(srv.sigil_catalog) is False
