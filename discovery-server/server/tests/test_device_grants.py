"""Task 1: журнал `device_grants` — per-device знание (анти-чит-ядро + восстановление Bug B).

Мутации-красные:
- убрать гейт `_corroborated_pair` в `_grant_recipe` → выдуманная пара принялась бы
  (assert `== -1` краснеет) — это дыра «заявил все скрытые пары».
- убрать запись `kind='element'`-гранта из `_grant_recipe` → `_element_granted`
  вернёт False → гейт Task 5 легитимную варку отклонит.
"""
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.abspath(os.path.join(HERE, ".."))
for _p in (SERVER_DIR,):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import seed  # noqa: E402
from server import (  # noqa: E402
    _corroborated_pair,
    _corroborated_element,
    _grant_recipe,
    _element_granted,
    _grants_for,
    BASE_SLUGS,
)


def _fresh_db(tmp_path):
    db = os.path.join(str(tmp_path), "grants.db")
    if os.path.exists(db):
        os.remove(db)
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    with open(os.path.join(SERVER_DIR, "schema.sql"), encoding="utf-8") as f:
        conn.executescript(f.read())
    seed.seed_db(conn)
    seed.seed_bots(conn)
    conn.commit()
    return conn


def _out_slug(conn, pair_key):
    row = conn.execute(
        "SELECT o.slug AS out FROM recipes r JOIN elements o ON o.id = r.out_id "
        "WHERE r.pair_key = ?", (pair_key,)
    ).fetchone()
    return row["out"]


def test_grant_recipe_accepts_base_but_rejects_hidden(tmp_path):
    conn = _fresh_db(tmp_path)
    base = conn.execute("SELECT pair_key, a, b FROM recipes LIMIT 1").fetchone()
    out_slug = _out_slug(conn, base["pair_key"])
    # базовая пара есть в recipes → корроборирована → грант принят
    assert _corroborated_pair(conn, base["pair_key"]) is True
    assert _grant_recipe(conn, "dev1", base["pair_key"], base["a"], base["b"],
                         out_slug, "local_learn") == 1
    # варка рецепта делает выходной элемент легитимным знанием (петля гейта Task 5)
    assert _element_granted(conn, "dev1", out_slug) is True
    # повтор идемпотентен
    assert _grant_recipe(conn, "dev1", base["pair_key"], base["a"], base["b"],
                         out_slug, "local_learn") == 0
    # выдуманная пара (нет в recipes, не world_first) → отказ, ничего не записано
    assert _grant_recipe(conn, "dev1", "zzz|qqq", "zzz", "qqq", "nope",
                         "local_learn") == -1
    recipes = [r for r in _grants_for(conn, "dev1") if r["kind"] == "recipe"]
    assert len(recipes) == 1 and recipes[0]["ref"] == base["pair_key"]
    conn.close()


def test_world_first_bypasses_corroboration(tmp_path):
    conn = _fresh_db(tmp_path)
    # world_first — источник доверяется без проверки наличия в recipes
    assert _corroborated_pair(conn, "newa|newb") is False
    assert _grant_recipe(conn, "devW", "newa|newb", "newa", "newb", "newout",
                         "world_first") == 1
    assert _element_granted(conn, "devW", "newout") is True
    conn.close()


def test_corroborated_element_covers_base_and_materialized(tmp_path):
    conn = _fresh_db(tmp_path)
    # базовый seed-slug (fire) — не в device_grants, но корроборирован как base
    assert "fire" in BASE_SLUGS
    assert _corroborated_element(conn, "fire") is True
    # выдуманный slug, которого нет ни в BASE_SLUGS, ни в elements
    assert _corroborated_element(conn, "ghost_undefined") is False
    conn.close()
