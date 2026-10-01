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
            "ether_cost": 40, "process": "искры из воздуха", "stage": "nigredo",
            "fallback_name": "Искра", "object_type": "object", "seed": 11,
        },
        {
            "id": "coal", "set": "fire", "rarity": "common",
            "recipe": [{"item_id": "fire", "qty": 14}, {"item_id": "stone", "qty": 9}],
            "ether_cost": 45, "process": "обугленное дерево", "stage": "nigredo",
            "fallback_name": "Уголь", "object_type": "object", "seed": 12,
        },
        {
            "id": "ice", "set": "water", "rarity": "rare",
            "recipe": [{"item_id": "water", "qty": 30}, {"item_id": "air", "qty": 20}],
            "ether_cost": 160, "process": "застывшая вода", "stage": "albedo",
            "fallback_name": "Лёд", "object_type": "object", "seed": 33,
        },
        {
            "id": "mist", "set": "water", "rarity": "rare",
            "recipe": [{"item_id": "water", "qty": 24}, {"item_id": "steam", "qty": 18}],
            "ether_cost": 150, "process": "туман над водой", "stage": "albedo",
            "fallback_name": "Туман", "object_type": "abstraction", "seed": 34,
        },
        {
            "id": "cloud", "set": "air", "rarity": "epic",
            "recipe": [{"item_id": "steam", "qty": 60}, {"item_id": "air", "qty": 70}],
            "ether_cost": 380, "process": "сгущение пара", "stage": "citrinitas",
            "fallback_name": "Облако", "object_type": "object", "seed": 44,
        },
        {
            "id": "smoke", "set": "air", "rarity": "epic",
            "recipe": [{"item_id": "fire", "qty": 55}, {"item_id": "plant", "qty": 40}],
            "ether_cost": 360, "process": "горение травы", "stage": "citrinitas",
            "fallback_name": "Дым", "object_type": "abstraction", "seed": 45,
        },
        {
            "id": "lava", "set": "earth", "rarity": "legendary",
            "recipe": [
                {"item_id": "stone", "qty": 120}, {"item_id": "fire", "qty": 150},
                {"item_id": "metal", "qty": 90}, {"item_id": "earth", "qty": 200},
            ],
            "ether_cost": 900, "process": "расплав глубин", "stage": "rubedo",
            "fallback_name": "Лава", "object_type": "abstraction", "seed": 22,
        },
        {
            "id": "stone", "set": "earth", "rarity": "common",
            "recipe": [{"item_id": "earth", "qty": 8}, {"item_id": "fire", "qty": 6}],
            "ether_cost": 35, "process": "спекшаяся глина", "stage": "nigredo",
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

    def test_non_dict_catalog_reports_error(self, tmp_path, monkeypatch):
        """Valid-но-не-объектный JSON (null/[...]) — та же пустая форма."""
        s = _srv(tmp_path, monkeypatch)
        path = tmp_path / "weird.json"
        monkeypatch.setattr(s, "SIGIL_CATALOG_PATH", str(path))
        for text in ("null", "[]"):
            path.write_text(text, encoding="utf-8")
            s._sigil_catalog_cache_clear()
            r = _client(s).get("/api/sigil/catalog")
            assert r.status_code == 200, text
            assert r.json()["error"] == "catalog_empty", text

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


class TestRealCatalogContract:
    """Контракт stage по РЕАЛЬНОМУ артефакту data/sigil_catalog.json.

    stage обязан дойти до моделей ответа строкой спек-формы: каталог хранит
    «nigredo»/«albedo»/…, и int-семантика (int("albedo"), stage: int в
    SigilCraft/SigilCatalogCard) падает на первой же карте.
    """

    STAGES = {"nigredo", "albedo", "citrinitas", "rubedo"}

    def test_catalog_craft_survives_all_100_cards(self):
        data = srv._sigil_catalog()
        assert len(data["cards"]) == 100
        assert {str(c.get("stage")) for c in data["cards"]} == self.STAGES
        for card in data["cards"]:
            craft = srv._catalog_craft(card, "2026-01-01", "dev-contract", 0)
            assert craft["stage"] in self.STAGES, card["id"]
            srv.SigilCraft(**craft)  # модель оффера обязана принять крафт как есть

    def test_catalog_response_model_accepts_real_artifact(self):
        data = srv._sigil_catalog()
        body = srv.SigilCatalogResponse(
            ok=True, version=data["version"], sets=data["sets"], cards=data["cards"]
        )
        assert len(body.cards) == 100
        assert {str(c.stage) for c in body.cards} == self.STAGES

    def test_sigil_endpoints_e2e_on_real_catalog(self, tmp_path, monkeypatch):
        client = _client(_srv(tmp_path, monkeypatch))
        r = client.get("/api/sigil/catalog")
        assert r.status_code == 200
        assert all(c["stage"] in self.STAGES for c in r.json()["cards"])
        r = client.get("/api/sigil/daily", params={"device_id": "dev-real"})
        assert r.status_code == 200
        crafts = r.json()["crafts"]
        assert all(
            c["stage"] in self.STAGES for c in crafts if not c["is_chromatic"]
        ), crafts
        r = client.post(
            "/api/sigil/craft",
            json={"device_id": "dev-real", "craft_id": crafts[0]["id"]},
        )
        assert r.status_code == 200
        r = client.post("/api/admin/sigil/rotate", params={"device_id": "dev-real"})
        assert r.status_code == 200
        assert all(c["stage"] in self.STAGES for c in r.json()["crafts"]), r.json()


import sqlite3  # noqa: E402  (нужен _seed_crafts)


def _seed_crafts(s, device_id, rows):
    """rows: [(craft_id, card_id), ...] — собрать карты в обход эндпоинта крафта."""
    conn = sqlite3.connect(s.DB_PATH)
    for craft_id, card_id in rows:
        conn.execute(
            "INSERT OR REPLACE INTO sigil_crafts"
            " (device_id, craft_id, rarity, llm_name, is_chromatic, card_id, crafted_at)"
            " VALUES (?, ?, 'common', '', 0, ?, '2026-01-01T00:00:00')",
            (device_id, craft_id, card_id),
        )
    conn.commit()
    conn.close()


def _offer(client, device_id):
    r = client.get("/api/sigil/daily", params={"device_id": device_id})
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True, body
    return body["crafts"]


class TestDailyOffer:
    def test_offer_has_three_distinct_catalog_cards(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        crafts = _offer(client, "dev-a")
        assert len(crafts) == srv._SIGIL_SLOTS
        ids = [c["card_id"] for c in crafts if c["card_id"]]
        assert len(set(ids)) == len(ids), "оффер не должен повторять карту"
        by_id = srv._sigil_catalog()["by_id"]
        for card_id in ids:
            assert card_id in by_id

    def test_offer_ingredients_come_from_the_card(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        by_id = srv._sigil_catalog()["by_id"]
        for c in _offer(client, "dev-a"):
            if not c["card_id"]:
                continue
            card = by_id[c["card_id"]]
            assert c["ingredients"] == card["recipe"]
            assert c["ether_cost"] == card["ether_cost"]
            assert c["rarity"] == card["rarity"]
            assert c["seed"] == card["seed"]
            assert c["fallback_name"] == card["fallback_name"]

    def test_offer_is_stable_within_a_day(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        first = _offer(client, "dev-a")
        second = _offer(client, "dev-a")
        assert first == second

    def test_offer_differs_between_players(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        offers = {
            tuple(c["card_id"] for c in _offer(client, f"dev-{i}"))
            for i in range(8)
        }
        assert len(offers) > 1

    def test_offer_guarantees_an_uncollected_card(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        all_ids = [c["id"] for c in srv._sigil_catalog()["cards"]]
        # Собираем всё, кроме двух карт: гарантия обязана дать одну из них.
        _seed_crafts(s, "dev-c", [(f"c{i}", cid) for i, cid in enumerate(all_ids[:-2])])
        srv._sigil_catalog_cache_clear()
        crafts = _offer(client, "dev-c")
        offered = {c["card_id"] for c in crafts if c["card_id"]}
        assert offered & set(all_ids[-2:]), crafts

    def test_full_collection_falls_back_to_chromatic_slot(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        all_ids = [c["id"] for c in srv._sigil_catalog()["cards"]]
        _seed_crafts(s, "dev-full", [(f"c{i}", cid) for i, cid in enumerate(all_ids)])
        crafts = _offer(client, "dev-full")
        assert crafts[0]["is_chromatic"] is True
        assert crafts[0]["card_id"] == ""
        assert crafts[0]["rarity"] == "chromatic"
        assert crafts[0]["ether_cost"] == srv._SIGIL_ETHER_COST["chromatic"]
        assert len(crafts[0]["ingredients"]) == srv._SIGIL_CHROMATIC_INGREDIENTS
        lo, hi = srv._SIGIL_CHROMATIC_QTY
        for ing in crafts[0]["ingredients"]:
            assert lo <= ing["qty"] <= hi

    def test_chromatic_is_rare(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        hits = sum(
            1 for i in range(200)
            if _offer(client, f"dev-{i}")[0]["is_chromatic"]
        )
        # 2% на 200 игроков: ждём единицы, но не ноль и не половину.
        assert 0 <= hits <= 20, hits

    def test_rarity_weights_are_rebalanced(self):
        assert srv._SIGIL_RARITY_WEIGHTS == [
            ("common", 70), ("rare", 20), ("epic", 8), ("legendary", 4),
        ]
        assert sum(w for _, w in srv._SIGIL_RARITY_WEIGHTS) == 102  # 70+20+8+4; бриф говорил "== 100", но с его же весами это недостижимо
        assert srv._SIGIL_ETHER_COST["chromatic"] == 1200

    def test_legacy_cache_is_regenerated(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        today = srv.date.today().isoformat()
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute(
            "INSERT INTO sigil_daily (device_id, day, crafts_json, generated_at)"
            " VALUES (?, ?, ?, ?)",
            ("dev-old", today, json.dumps([{"id": "x", "ingredients": [], "ether_cost": 1,
                                            "rarity": "common"}]), "2020-01-01T00:00:00"),
        )
        conn.commit()
        conn.close()
        crafts = _offer(client, "dev-old")
        assert [c["id"] for c in crafts] != ["x"]
        assert all("card_id" in c for c in crafts)

    def test_missing_device_id_rejected(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.get("/api/sigil/daily")
        assert r.json() == {"ok": False, "day": "", "crafts": [], "error": "missing_device_id"}

    def test_rotate_gives_catalog_cards(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.post("/api/admin/sigil/rotate", params={"device_id": "dev-a"})
        assert r.status_code == 200
        body = r.json()
        assert body["ok"] is True
        assert len(body["crafts"]) == srv._SIGIL_SLOTS
        assert all("card_id" in c for c in body["crafts"])


class TestCraft:
    def test_craft_records_card_id(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        target = next(c for c in _offer(client, "dev-a") if c["card_id"])
        r = client.post("/api/sigil/craft",
                        json={"device_id": "dev-a", "craft_id": target["id"]})
        assert r.status_code == 200
        assert r.json() == {
            "ok": True, "craft_id": target["id"], "rarity": target["rarity"],
            "llm_name": target["llm_name"], "is_chromatic": False,
            "card_id": target["card_id"], "error": "",
        }
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-a"}).json()
        entry = coll["cards"][target["card_id"]]
        assert entry["copies"] == 1
        assert entry["first_at"] != ""

    def test_recraft_is_idempotent(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        target = next(c for c in _offer(client, "dev-a") if c["card_id"])
        first = client.post("/api/sigil/craft",
                            json={"device_id": "dev-a", "craft_id": target["id"]}).json()
        second = client.post("/api/sigil/craft",
                             json={"device_id": "dev-a", "craft_id": target["id"]}).json()
        assert second == first
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-a"}).json()
        assert coll["cards"][target["card_id"]]["copies"] == 1

    def test_copies_accumulate(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        target = next(c for c in _offer(client, "dev-a") if c["card_id"])
        client.post("/api/sigil/craft",
                    json={"device_id": "dev-a", "craft_id": target["id"]})
        # Та же карта, другой день (craft_id другой) -> вторая копия.
        _seed_crafts(s, "dev-a", [("yesterday_0", target["card_id"])])
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-a"}).json()
        assert coll["cards"][target["card_id"]]["copies"] == 2

    def test_unknown_craft_rejected(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.post("/api/sigil/craft", json={"device_id": "dev-a", "craft_id": "nope"})
        assert r.json() == {
            "ok": False, "craft_id": "nope", "rarity": "", "llm_name": "",
            "is_chromatic": False, "card_id": "", "error": "craft_not_found",
        }

    def test_missing_device_id_rejected(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.post("/api/sigil/craft", json={"device_id": "", "craft_id": "x"})
        assert r.status_code == 422  # SigilCraftRequest: min_length=1

    def test_card_outside_catalog_rejected(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        today = srv.date.today().isoformat()
        forged = [{
            "id": f"{today}_dev-fake_0", "card_id": "not_a_card", "set": "",
            "rarity": "legendary", "ingredients": [], "ether_cost": 1,
            "process": "", "stage": 0, "object_type": "object", "seed": 0,
            "fallback_name": "Подделка", "llm_name": "", "is_chromatic": False,
        }]
        conn = sqlite3.connect(s.DB_PATH)
        conn.execute(
            "INSERT INTO sigil_daily (device_id, day, crafts_json, generated_at)"
            " VALUES (?, ?, ?, ?)",
            ("dev-fake", today, json.dumps(forged, ensure_ascii=False), "2026-01-01T00:00:00"),
        )
        conn.commit()
        conn.close()
        r = client.post("/api/sigil/craft",
                        json={"device_id": "dev-fake", "craft_id": forged[0]["id"]})
        assert r.json()["error"] == "card_not_in_catalog"
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-fake"}).json()
        assert coll["cards"] == {}

    def test_chromatic_craft_goes_to_extras(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        all_ids = [c["id"] for c in srv._sigil_catalog()["cards"]]
        _seed_crafts(s, "dev-full", [(f"c{i}", cid) for i, cid in enumerate(all_ids)])
        chroma = _offer(client, "dev-full")[0]
        assert chroma["is_chromatic"] is True
        r = client.post("/api/sigil/craft",
                        json={"device_id": "dev-full", "craft_id": chroma["id"]}).json()
        assert r["ok"] is True
        assert r["card_id"] == ""
        assert r["is_chromatic"] is True
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-full"}).json()
        assert len(coll["extras"]) == 1
        assert coll["extras"][0]["craft_id"] == chroma["id"]
        assert coll["extras"][0]["rarity"] == "chromatic"
        assert len(coll["cards"]) == len(all_ids)


class TestCollection:
    def test_missing_device_id_rejected(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.get("/api/sigil/collection")
        assert r.json() == {
            "ok": False, "cards": {}, "extras": [], "error": "missing_device_id",
        }

    def test_empty_collection(self, tmp_path, monkeypatch):
        client = _mini(_srv(tmp_path, monkeypatch), tmp_path, monkeypatch)
        r = client.get("/api/sigil/collection", params={"device_id": "dev-none"})
        assert r.json() == {"ok": True, "cards": {}, "extras": [], "error": ""}

    def test_first_at_is_the_earliest_copy(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        client = _mini(s, tmp_path, monkeypatch)
        conn = sqlite3.connect(s.DB_PATH)
        # Вставляем ПОЗДНЮЮ копию первой: порядок чтения обязан чиниться ORDER BY.
        for craft_id, at in [("b_late", "2026-05-05T00:00:00"),
                             ("a_early", "2026-01-01T00:00:00")]:
            conn.execute(
                "INSERT INTO sigil_crafts"
                " (device_id, craft_id, rarity, llm_name, is_chromatic, card_id, crafted_at)"
                " VALUES (?, ?, 'common', '', 0, 'spark', ?)",
                ("dev-t", craft_id, at),
            )
        conn.commit()
        conn.close()
        coll = client.get("/api/sigil/collection", params={"device_id": "dev-t"}).json()
        assert coll["cards"]["spark"] == {"copies": 2, "first_at": "2026-01-01T00:00:00"}


class TestMigration:
    def test_legacy_rows_survive_migration(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        legacy = tmp_path / "legacy.db"
        conn = sqlite3.connect(legacy)
        conn.execute("""CREATE TABLE sigil_crafts (
            device_id TEXT NOT NULL, craft_id TEXT NOT NULL,
            rarity TEXT NOT NULL, llm_name TEXT NOT NULL DEFAULT '',
            is_chromatic INTEGER NOT NULL DEFAULT 0,
            crafted_at TEXT NOT NULL,
            PRIMARY KEY (device_id, craft_id))""")
        conn.execute(
            "INSERT INTO sigil_crafts"
            " (device_id, craft_id, rarity, llm_name, is_chromatic, crafted_at)"
            " VALUES ('dev-legacy', 'old_1', 'epic', 'Старый', 0, '2026-01-01T00:00:00')")
        conn.commit()
        conn.close()

        monkeypatch.setattr(s, "DB_PATH", str(legacy))
        client = _mini(s, tmp_path, monkeypatch)  # _mini зовёт init_db() -> миграция

        conn = sqlite3.connect(str(legacy))
        cols = {r[1] for r in conn.execute("PRAGMA table_info(sigil_crafts)")}
        conn.close()
        assert "card_id" in cols

        coll = client.get("/api/sigil/collection", params={"device_id": "dev-legacy"}).json()
        assert coll["ok"] is True
        assert coll["cards"] == {}
        # Пустой card_id у legacy-строки -> extras, а не падение.
        assert len(coll["extras"]) == 1
        assert coll["extras"][0]["craft_id"] == "old_1"
        assert coll["extras"][0]["llm_name"] == "Старый"

    def test_card_index_exists(self, tmp_path, monkeypatch):
        s = _srv(tmp_path, monkeypatch)
        _mini(s, tmp_path, monkeypatch)
        conn = sqlite3.connect(s.DB_PATH)
        names = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index'")}
        conn.close()
        assert "ix_sigil_crafts_card" in names


class TestContract:
    def test_new_handlers_are_sync(self):
        # T29: хендлеры, трогающие БД, обязаны быть sync def.
        assert inspect.iscoroutinefunction(srv.sigil_craft) is False
        assert inspect.iscoroutinefunction(srv.sigil_collection) is False
