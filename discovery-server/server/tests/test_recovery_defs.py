"""Task 3: _recovered_defs — определение потерянных рецептов по инвентарю.

Recovery: у игрока в инвентаре есть выходной элемент, определение пары которого
материализовано в `recipes` (кем-то сварено / world-first). Сервер отдаёт пару
{pair_key,a,b,out}, чтобы клиент восстановил recipe-грант (account_export).
Скрытый нераскрытый каталог не просочивается: ищем строго по таблице recipes.

Мутации-красные:
- вернуть определение по slug из elements без JOIN на recipes → покраснеет
  test_recovered_defs_ignores_held_without_definition (у fire есть элемент, но
  recipe-определения нет).
- grant rejected для recovered-пары → покраснеет accept-ассерт (corroboration-дыра).
"""
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.abspath(os.path.join(HERE, ".."))
for _p in (SERVER_DIR, os.path.abspath(os.path.join(SERVER_DIR, ".."))):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import server as srv  # noqa: E402


def _fresh_db(tmp_path):
    db = os.path.join(str(tmp_path), "recovery.db")
    if os.path.exists(db):
        os.remove(db)
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    with open(os.path.join(SERVER_DIR, "schema.sql"), encoding="utf-8") as f:
        conn.executescript(f.read())
    import seed
    seed.seed_db(conn)
    conn.commit()
    return conn


def _eid(conn, slug):
    return conn.execute("SELECT id FROM elements WHERE slug = ?", (slug,)).fetchone()["id"]


def materialize_pair(conn, a_slug, b_slug, out_slug):
    """Вставить world-first-подобную пару: выходной элемент + строка recipes."""
    if conn.execute("SELECT 1 FROM elements WHERE slug = ?", (out_slug,)).fetchone() is None:
        conn.execute(
            "INSERT INTO elements (slug, name, color, layer, category) VALUES (?,?,?,?,?)",
            (out_slug, out_slug.capitalize(), "#123456", 4, "misc"),
        )
    key = (a_slug + "|" + b_slug) if a_slug <= b_slug else (b_slug + "|" + a_slug)
    conn.execute(
        "INSERT INTO recipes (pair_key, a, b, a_id, b_id, out_id, discoverer_device) "
        "VALUES (?,?,?,?,?,?,?)",
        (key, a_slug, b_slug, _eid(conn, a_slug), _eid(conn, b_slug), _eid(conn, out_slug), "bot-0"),
    )
    conn.commit()
    return key


def test_recovered_defs_returns_recipe_def_for_held_generated_element(tmp_path):
    conn = _fresh_db(tmp_path)
    # пара ice+gold не сидирована seed-ом (иначе pair_key конфликтует с базовым рецептом)
    key = materialize_pair(conn, "ice", "gold", "wonder")
    defs = srv._recovered_defs(conn, ["wonder", "fire"])
    assert any(d["out"] == "wonder" and d["pair_key"] == key for d in defs)
    d = next(x for x in defs if x["out"] == "wonder")
    # пара корроборирована (есть в recipes) → grant account_export обязан принять
    assert srv._grant_recipe(conn, "devR", d["pair_key"], d["a"], d["b"], d["out"], "account_export") >= 0
    conn.close()


def test_recovered_defs_ignores_held_without_definition(tmp_path):
    conn = _fresh_db(tmp_path)
    # 'fire' — базовый элемент без собственного recipe-определения (не выход)
    defs = srv._recovered_defs(conn, ["fire"])
    assert all(d["out"] != "fire" for d in defs)
    conn.close()


def test_recovered_defs_dedups_by_pair_key(tmp_path):
    conn = _fresh_db(tmp_path)
    materialize_pair(conn, "ice", "gold", "wonder")
    # инвентарь с дублями и одним элементом-выходом дважды
    defs = srv._recovered_defs(conn, ["wonder", "wonder", "wonder"])
    keys = [d["pair_key"] for d in defs if d["out"] == "wonder"]
    assert len(keys) == len(set(keys))
    conn.close()
