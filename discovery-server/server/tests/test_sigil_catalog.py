"""Каталог карт Аркана Сигилов: инварианты, детерминизм, отсутствие дрейфа.

Закоммиченный data/sigil_catalog.json обязан байт-в-байт совпадать с тем, что
даёт tools/gen_sigil_catalog.py: каталог — артефакт сборки, а не ручные данные.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

SERVER_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = SERVER_DIR.parent.parent
CLIENT_DIR = REPO_DIR / "alchemists-loop"
GEN = CLIENT_DIR / "tools" / "gen_sigil_catalog.py"
CATALOG = SERVER_DIR / "data" / "sigil_catalog.json"

SETS = {"fire", "water", "air", "earth"}
RARITY_COUNTS = {"common": 12, "rare": 7, "epic": 4, "legendary": 2}
PROCESSES = {"calcinatio", "sublimatio", "distillatio", "putrefactio", "coniunctio"}
STAGES = {"nigredo", "albedo", "citrinitas", "rubedo"}
STAGE_BY_RARITY = {
    "common": "nigredo", "rare": "albedo",
    "epic": "citrinitas", "legendary": "rubedo",
}
ETHER_BY_RARITY = {"common": 50, "rare": 150, "epic": 400, "legendary": 800}
QTY_BY_RARITY = {
    "common": (6, 14), "rare": (8, 20), "epic": (12, 30), "legendary": (18, 45),
}


@pytest.fixture(scope="module")
def catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def _run_gen(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(GEN), *args], capture_output=True, text=True, encoding="utf-8"
    )


def test_committed_catalog_has_no_drift() -> None:
    """Краснеет, если JSON в репо правили руками или изменились ITEMS/RECIPES."""
    proc = _run_gen("--check")
    assert proc.returncode == 0, proc.stdout + proc.stderr


def test_generator_is_deterministic(tmp_path: Path) -> None:
    for name in ("a.json", "b.json"):
        proc = _run_gen("--out", str(tmp_path / name))
        assert proc.returncode == 0, proc.stdout + proc.stderr
    assert (tmp_path / "a.json").read_bytes() == (tmp_path / "b.json").read_bytes()


def test_catalog_top_level(catalog: dict) -> None:
    assert len(catalog["cards"]) == 100
    assert len(catalog["sets"]) == 4
    assert len(catalog["version"]) == 16
    assert all(c in "0123456789abcdef" for c in catalog["version"])
    assert {s["id"] for s in catalog["sets"]} == SETS


def test_sets_partition_the_cards(catalog: dict) -> None:
    ids = [c["id"] for c in catalog["cards"]]
    assert len(set(ids)) == 100
    flat: list[str] = []
    for s in catalog["sets"]:
        assert len(s["card_ids"]) == 25, s["id"]
        assert s["title"], s["id"]
        flat.extend(s["card_ids"])
    assert sorted(flat) == sorted(ids)


def test_card_matches_its_set(catalog: dict) -> None:
    by_set = {s["id"]: set(s["card_ids"]) for s in catalog["sets"]}
    for card in catalog["cards"]:
        assert card["id"] in by_set[card["set"]]


def test_card_fields(catalog: dict) -> None:
    for card in catalog["cards"]:
        assert card["set"] in SETS
        assert card["rarity"] in ETHER_BY_RARITY
        assert card["ether_cost"] == ETHER_BY_RARITY[card["rarity"]]
        assert card["process"] in PROCESSES
        assert card["stage"] in STAGES
        assert card["stage"] == STAGE_BY_RARITY[card["rarity"]]
        assert card["fallback_name"]
        assert card["object_type"]
        assert 0 < card["seed"] < 2 ** 48
        # R5: seed — чистая функция id (без соли игрока), основа «арт одинаков у всех».
        assert card["seed"] == int(hashlib.sha256(("sigil-card#" + card["id"]).encode("utf-8")).hexdigest()[:12], 16)
        assert 3 <= len(card["recipe"]) <= 4
        seen: set[str] = set()
        for ing in card["recipe"]:
            assert ing["item_id"]
            assert ing["item_id"] != card["id"]
            assert ing["item_id"] not in seen
            seen.add(ing["item_id"])
            lo, hi = QTY_BY_RARITY[card["rarity"]]
            assert lo <= ing["qty"] <= hi


def test_rarity_counts_per_set(catalog: dict) -> None:
    by_id = {c["id"]: c for c in catalog["cards"]}
    for s in catalog["sets"]:
        counts = dict.fromkeys(RARITY_COUNTS, 0)
        for cid in s["card_ids"]:
            counts[by_id[cid]["rarity"]] += 1
        assert counts == RARITY_COUNTS, s["id"]


def test_excluded_cards_are_not_in_catalog(catalog: dict) -> None:
    ids = {c["id"] for c in catalog["cards"]}
    assert len(catalog["excluded"]) == 9
    assert not (ids & set(catalog["excluded"]))


def test_version_follows_cards(catalog: dict) -> None:
    blob = json.dumps(
        catalog["cards"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    assert hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16] == catalog["version"]
