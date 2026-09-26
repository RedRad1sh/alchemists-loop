#!/usr/bin/env python3
"""
clean_db.py — чистка БД первооткрытий от мусорных комбинаций.

Что считается «мусором»:
  * сгенерированные рецепты/вещества (author IS NOT NULL) — всё, что LLM
    или локальный генератор добавили поверх стартового графа;
  * rejected_pairs — пары, помеченные «не сочетается» (можно снять, чтобы
    пара генерировалась заново);
  * world_events — лента событий мира (необязательно).

Стартовый граф (57 веществ / 53 рецепта из seed.py) НЕ трогается.

Команды:
  python3 clean_db.py list [путь_к_БД]
      Показать все сгенерированные рецепты+вещества, отказы и события.

  python3 clean_db.py rm <слаг|имя> [--cascade] [путь_к_БД]
      Удалить сгенерированный рецепт и его выходное вещество.
      Если вещество используется как ингредиент в других рецептах — без
      --cascade команда откажется и покажет зависимые рецепты.
      С --cascade удаляются и все зависимые рецепты (цепочкой вниз).

  python3 clean_db.py unreject <pair_key|a,b> [путь_к_БД]
      Убрать пару из rejected_pairs, чтобы её можно было сгенерировать заново.
      Примеры: "wall|wall" или "wall,wall" или "стена,стена".

  python3 clean_db.py reset [--also-events] [путь_к_БД]
      Полный сброс первооткрытий: остаётся только чистый стартовый граф.
      С --also-events дополнительно очищается лента событий мира.

По умолчанию берётся ALCHEMY_DB_PATH/DB_PATH из окружения или пользовательская
папка данных (см. server.py).
Перед чисткой остановите сервер (uvicorn), чтобы не было конфликта записей.
"""

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "server"))

import server as srv  # noqa: E402
import seed  # noqa: E402


def _default_db() -> str:
    if os.environ.get("ALCHEMY_DB_PATH") or os.environ.get("DB_PATH"):
        return os.environ.get("ALCHEMY_DB_PATH") or os.environ.get("DB_PATH")
    import server as _srv
    return _srv.DB_PATH


def _seed_slugs() -> set:
    return set(seed.ITEMS.keys())


def _seed_pair_keys() -> set:
    keys = set()
    for a, b, _out in seed.RECIPES:
        keys.add(a + "|" + b if a <= b else b + "|" + a)
    return keys


def _open(db_path: str):
    if not os.path.exists(db_path):
        print(f"БД не найдена: {db_path}")
        sys.exit(1)
    srv.DB_PATH = db_path
    srv.init_db()
    return srv.get_db()


def _canon(a: str, b: str) -> str:
    return a + "|" + b if a <= b else b + "|" + a


# ---------------------------------------------------------------------------
def cmd_list(conn) -> None:
    seed_slugs = _seed_slugs()
    print("=== Сгенерированные вещества (вне стартового графа) ===")
    rows = conn.execute(
        "SELECT slug, name, layer, category, author, created_at FROM elements "
        "WHERE author IS NOT NULL ORDER BY layer, name"
    ).fetchall()
    if not rows:
        print("  (нет)")
    for r in rows:
        print(f"  {r['slug']:<18} {r['name']:<20} слой {r['layer']:<2} автор {r['author']}")

    print("\n=== Сгенерированные рецепты ===")
    rows = conn.execute(
        """SELECT r.pair_key, r.a, r.b, e.name AS out_name, e.slug AS out_slug, r.discoverer
           FROM recipes r JOIN elements e ON e.id = r.out_id
           WHERE r.discoverer IS NOT NULL
           ORDER BY e.layer, e.name"""
    ).fetchall()
    if not rows:
        print("  (нет)")
    for r in rows:
        print(f"  {r['pair_key']:<22} -> {r['out_name']} ({r['out_slug']}) автор {r['discoverer']}")

    print("\n=== Отказы (rejected_pairs) ===")
    rows = conn.execute("SELECT pair_key, created_at FROM rejected_pairs ORDER BY pair_key").fetchall()
    if not rows:
        print("  (нет)")
    for r in rows:
        print(f"  {r['pair_key']:<22} ({r['created_at']})")

    print("\n=== Лента событий мира (world_events) ===")
    n = conn.execute("SELECT COUNT(*) AS c FROM world_events").fetchone()["c"]
    print(f"  {n} записей")


# ---------------------------------------------------------------------------
def _find_element(conn, token: str):
    """Найти сгенерированный элемент по слагу или имени (регистронезависимо).
    Возвращает строку, None или строку 'AMBIG'."""
    token_l = token.strip().lower()
    rows = conn.execute(
        "SELECT id, slug, name, layer FROM elements WHERE author IS NOT NULL ORDER BY id"
    ).fetchall()
    hits = [r for r in rows if r["slug"].lower() == token_l or r["name"].lower() == token_l]
    if not hits:
        return None
    if len(hits) > 1:
        print(f"Неоднозначно «{token}» — совпадений несколько, уточните слаг:")
        for r in hits:
            print(f"  {r['slug']} ({r['name']})")
        return "AMBIG"
    return hits[0]


def _recipe_of(conn, element_id: int):
    return conn.execute("SELECT * FROM recipes WHERE out_id = ?", (element_id,)).fetchone()


def _dependent_recipes(conn, element_id: int):
    return conn.execute(
        "SELECT * FROM recipes WHERE a_id = ? OR b_id = ? ORDER BY id", (element_id, element_id)
    ).fetchall()


def _delete_recipe_and_element(conn, recipe, cascade: bool, stack: list) -> None:
    """Рекурсивно удалить рецепт и его выходной элемент (и зависимые рецепты при cascade)."""
    pair_key = recipe["pair_key"]
    out_id = recipe["out_id"]
    el = conn.execute("SELECT id, slug, name FROM elements WHERE id = ?", (out_id,)).fetchone()
    if el is None:
        return
    if el["slug"] in _seed_slugs():
        print(f"  пропуск: «{el['name']}» ({el['slug']}) — стартовое вещество, не трогаем")
        return

    deps = _dependent_recipes(conn, out_id)
    if deps and not cascade:
        print(f"  ! «{el['name']}» используется как ингредиент в {len(deps)} рецептах:")
        for d in deps:
            de = conn.execute("SELECT name FROM elements WHERE id = ?", (d["out_id"],)).fetchone()
            print(f"      {d['pair_key']} -> {de['name'] if de else '?'}")
        print("    Добавьте --cascade, чтобы удалить их цепочкой.")
        return

    # зависимые рецепты — сначала (в глубину)
    for d in deps:
        _delete_recipe_and_element(conn, d, cascade, stack)

    conn.execute("DELETE FROM world_events WHERE pair_key = ?", (pair_key,))
    conn.execute("DELETE FROM pending_pairs WHERE pair_key = ?", (pair_key,))
    conn.execute("DELETE FROM recipes WHERE id = ?", (recipe["id"],))
    conn.execute("DELETE FROM elements WHERE id = ?", (out_id,))
    stack.append(f"рецепт {pair_key} -> «{el['name']}» ({el['slug']})")


def cmd_rm(conn, token: str, cascade: bool) -> None:
    el = _find_element(conn, token)
    if el is None:
        print(f"Сгенерированное вещество «{token}» не найдено (стартовые удалять нельзя).")
        sys.exit(1)
    if el == "AMBIG":
        sys.exit(1)
    recipe = _recipe_of(conn, el["id"])
    if recipe is None:
        print(f"У вещества «{el['name']}» нет производящего рецепта — пропуск.")
        return
    removed = []
    _delete_recipe_and_element(conn, recipe, cascade, removed)
    conn.commit()
    if removed:
        print("Удалено:")
        for line in removed:
            print("  - " + line)
    else:
        print("Ничего не удалено.")


# ---------------------------------------------------------------------------
def cmd_unreject(conn, token: str) -> None:
    token = token.strip()
    if "," in token:
        a, b = (x.strip() for x in token.split(",", 1))
        key = _canon(a, b)
    else:
        key = token
    cur = conn.execute("SELECT 1 FROM rejected_pairs WHERE pair_key = ?", (key,)).fetchone()
    if not cur:
        # попробуем подобрать по вхождениям
        like = conn.execute(
            "SELECT pair_key FROM rejected_pairs WHERE pair_key LIKE ?", ("%" + key + "%",)
        ).fetchall()
        if like:
            print(f"Точного ключа «{key}» нет. Похожие:")
            for r in like:
                print(f"  {r['pair_key']}")
            sys.exit(1)
        print(f"Пары «{key}» нет в rejected_pairs.")
        sys.exit(1)
    conn.execute("DELETE FROM rejected_pairs WHERE pair_key = ?", (key,))
    conn.commit()
    print(f"Пара {key} снята с отказов — теперь её можно сгенерировать заново.")


# ---------------------------------------------------------------------------
def cmd_reset(conn, also_events: bool) -> None:
    srv.reset_world(conn)
    if also_events:
        conn.execute("DELETE FROM world_events")
    conn.commit()
    n = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
    r = conn.execute("SELECT COUNT(*) AS c FROM recipes").fetchone()["c"]
    e = conn.execute("SELECT COUNT(*) AS c FROM world_events").fetchone()["c"]
    print(f"Готово: {n} веществ / {r} рецептов (чистый стартовый граф), событий в ленте: {e}.")


# ---------------------------------------------------------------------------
def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        sys.exit(0)

    cmd = args[0]
    rest = [a for a in args[1:] if not a.startswith("--")]
    flags = [a for a in args[1:] if a.startswith("--")]

    # путь к БД — последний не-флаговый аргумент, если он есть и не нужен команде
    db_path = _default_db()
    if cmd == "list":
        if rest:
            db_path = rest[-1]
    elif cmd in ("rm", "unreject"):
        if not rest:
            print(f"Нужен аргумент. См. `python3 clean_db.py help`.")
            sys.exit(1)
        token = rest[0]
        if len(rest) > 1:
            db_path = rest[-1]
    elif cmd == "reset":
        if rest:
            db_path = rest[-1]
    else:
        print(f"Неизвестная команда «{cmd}». См. `python3 clean_db.py help`.")
        sys.exit(1)

    conn = _open(db_path)
    try:
        if cmd == "list":
            cmd_list(conn)
        elif cmd == "rm":
            cmd_rm(conn, token, "--cascade" in flags)
        elif cmd == "unreject":
            cmd_unreject(conn, token)
        elif cmd == "reset":
            cmd_reset(conn, "--also-events" in flags)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
