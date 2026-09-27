"""Issue #13 (каскад clean_db без висячих ссылок) и #17 (bot-атрибуция seed-
рецептов отделена от player-находок).

Мутации-красные:
- test_seed_output_recipe_is_removed: вернуть в _delete_recipe_and_element
  ранний `return` по seed-slug без удаления строки рецепта — покраснеет
  (рецепт повиснет на удалённом a_id).
- test_all_producing_recipes_removed: вернуть `_recipe_of` (один рецепт) без
  цикла по всем производящим — покраснеет dangling-отчёт.
- test_cycle_terminates: убрать visiting-множество — RecursionError.
- test_seed_bots_mark_device_attribution: убрать запись discoverer_device в
  seed_bots — покраснеет она.
- test_cmd_list_hides_bot_seed_rows: убрать фильтр _seed_pair_keys в cmd_list —
  покраснеет она (Боровик вернётся в «сгенерированные»).
"""
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.abspath(os.path.join(HERE, ".."))
ROOT_DIR = os.path.abspath(os.path.join(SERVER_DIR, ".."))
for _p in (SERVER_DIR, ROOT_DIR):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import seed      # noqa: E402
import clean_db  # noqa: E402


def _fresh_db(tmp_path):
    db = os.path.join(str(tmp_path), "hygiene.db")
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


def _add_element(conn, slug, name, author="tester"):
    cur = conn.execute(
        "INSERT INTO elements (slug, name, color, layer, category, author, author_device) "
        "VALUES (?, ?, '#123456', 3, 'misc', ?, 'dev-tester')",
        (slug, name, author),
    )
    return cur.lastrowid


def _eid(conn, slug):
    return conn.execute("SELECT id FROM elements WHERE slug = ?", (slug,)).fetchone()["id"]


def _add_recipe(conn, key, a_slug, b_slug, out_slug_or_id):
    out_id = (out_slug_or_id if isinstance(out_slug_or_id, int)
              else _eid(conn, out_slug_or_id))
    cur = conn.execute(
        "INSERT INTO recipes (pair_key, a, b, a_id, b_id, out_id, discoverer, discoverer_device) "
        "VALUES (?, ?, ?, ?, ?, ?, 'tester', 'dev-tester')",
        (key, a_slug, b_slug, _eid(conn, a_slug), _eid(conn, b_slug), out_id),
    )
    return cur.lastrowid


# --------------------------------------------------------------------------- #
# Issue #13
# --------------------------------------------------------------------------- #
def test_noncascade_refuses_when_element_has_dependents(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_w", "Вода-база", author=None)
    x = _add_element(conn, "gen_x", "Икс")
    _add_element(conn, "gen_y", "Игрек")
    _add_recipe(conn, "gen_w|gen_x_src", "water", "gen_w", x)
    _add_recipe(conn, "gen_x|gen_w2", "gen_x", "gen_w", "gen_y")
    capsys.readouterr()
    clean_db.cmd_rm(conn, "gen_x", cascade=False)
    out = capsys.readouterr().out
    assert "--cascade" in out
    assert conn.execute("SELECT 1 FROM elements WHERE id = ?", (x,)).fetchone() is not None
    conn.close()


def test_cascade_deletes_chain_without_dangling(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_w", "Вода-база", author=None)
    x = _add_element(conn, "gen_x", "Икс")
    y = _add_element(conn, "gen_y", "Игрек")
    _add_recipe(conn, "gen_w|gen_x_src", "water", "gen_w", x)
    _add_recipe(conn, "gen_x|gen_w2", "gen_x", "gen_w", y)
    capsys.readouterr()
    clean_db.cmd_rm(conn, "gen_x", cascade=True)
    assert conn.execute("SELECT 1 FROM elements WHERE id = ?", (x,)).fetchone() is None
    assert conn.execute("SELECT 1 FROM elements WHERE id = ?", (y,)).fetchone() is None
    assert clean_db._dangling_report(conn) == []
    conn.close()


def test_all_producing_recipes_removed(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_w", "Вода-база", author=None)
    _add_element(conn, "gen_v", "Пар-база", author=None)
    x = _add_element(conn, "gen_x", "Икс")
    _add_recipe(conn, "gen_w|gen_x_src", "water", "gen_w", x)
    _add_recipe(conn, "gen_v|gen_x_src", "gen_v", "steam", x)
    capsys.readouterr()
    clean_db.cmd_rm(conn, "gen_x", cascade=True)
    n = conn.execute("SELECT COUNT(*) AS c FROM recipes WHERE out_id = ?", (x,)).fetchone()["c"]
    assert n == 0, "оба производящих рецепта должны быть удалены до элемента"
    assert clean_db._dangling_report(conn) == []
    conn.close()


def test_seed_output_recipe_is_removed_seed_kept(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_w", "Вода-база", author=None)
    x = _add_element(conn, "gen_x", "Икс")
    _add_recipe(conn, "gen_w|gen_x_src", "water", "gen_w", x)
    stone = _eid(conn, "stone")
    _add_recipe(conn, "gen_x|gen_w2", "gen_x", "gen_w", stone)
    capsys.readouterr()
    clean_db.cmd_rm(conn, "gen_x", cascade=True)
    assert conn.execute("SELECT 1 FROM recipes WHERE pair_key = 'gen_x|gen_w2'").fetchone() is None, \
        "рецепт с удаляемым ингредиентом и стартовым выходом обязан удалиться"
    assert conn.execute("SELECT 1 FROM elements WHERE id = ?", (stone,)).fetchone() is not None, \
        "стартовое вещество не удаляется"
    assert clean_db._dangling_report(conn) == []
    conn.close()


def test_cycle_terminates(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_p", "База-П", author=None)
    x = _add_element(conn, "gen_x", "Икс")
    y = _add_element(conn, "gen_y", "Игрек")
    _add_recipe(conn, "gen_p|gen_y", "gen_p", "gen_y", x)   # (p, y) -> x
    _add_recipe(conn, "gen_b|gen_x", "gen_p", "gen_x", y)   # (p, x) -> y
    capsys.readouterr()
    clean_db.cmd_rm(conn, "gen_x", cascade=True)  # без visiting-множества — RecursionError
    assert clean_db._dangling_report(conn) == []
    conn.close()


def test_dangling_report_flags_manual_dangling(tmp_path):
    conn = _fresh_db(tmp_path)
    conn.execute(
        "INSERT INTO recipes (pair_key, a, b, a_id, b_id, out_id) VALUES "
        "('bad|dangling', 'bad', 'dangling', 999999, NULL, "
        "(SELECT id FROM elements WHERE slug = 'water'))"
    )
    conn.commit()
    problems = clean_db._dangling_report(conn)
    assert any("bad|dangling" in p and "a_id" in p for p in problems)
    conn.close()


# --------------------------------------------------------------------------- #
# Issue #17
# --------------------------------------------------------------------------- #
def test_seed_bots_mark_device_attribution(tmp_path):
    conn = _fresh_db(tmp_path)
    row = conn.execute(
        "SELECT discoverer, discoverer_device FROM recipes WHERE discoverer = 'Боровик'"
    ).fetchone()
    assert row is not None
    assert row["discoverer_device"] == "bot-0", \
        "бот-атрибуция обязана быть различима по device, а не только по нику"
    conn.close()


def test_seed_bots_backfill_marks_existing_rows(tmp_path):
    conn = _fresh_db(tmp_path)
    # имитируем старую БД: бот-строка без device (как писал seed_bots до фикса)
    conn.execute("UPDATE recipes SET discoverer_device = NULL WHERE discoverer = 'Боровик'")
    conn.commit()
    seed.seed_bots(conn)
    row = conn.execute(
        "SELECT discoverer_device FROM recipes WHERE discoverer = 'Боровик'"
    ).fetchone()
    assert row["discoverer_device"] == "bot-0"
    conn.close()


def test_seed_bots_skip_taken_nicks(tmp_path):
    conn = _fresh_db(tmp_path)
    # реалистичный T02-ход: ник бота достался живому игроку — при дедупе
    # UNIQUE(nick) строка бота уходит, остаётся устройство-владелец ника
    conn.execute("DELETE FROM players WHERE device_id = 'bot-2'")
    conn.execute(
        "INSERT INTO players (nick, device_id) VALUES ('Луна', 'real-player-dev')"
    )
    conn.commit()
    seed.seed_bots(conn)
    row = conn.execute(
        "SELECT discoverer, discoverer_device FROM recipes "
        "WHERE pair_key = (SELECT pair_key FROM recipes ORDER BY pair_key LIMIT 1 OFFSET 2)"
    ).fetchone()
    # третий по pair_key рецепт — слот «Луна»; занятый ник не получает открытий,
    # а прежняя бот-атрибуция отзывается (иначе витрина по нику засчитала бы
    # seed-открытие живому игроку)
    assert row["discoverer"] != "Луна"
    conn.close()


def test_cmd_list_hides_bot_seed_rows(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    clean_db.cmd_list(conn)
    out = capsys.readouterr().out
    assert "Боровик" not in out, "бот-атрибуция стартового графа — не сгенерированное открытие"
    assert "Кремень" not in out
    conn.close()


def test_cmd_list_still_shows_generated(tmp_path, capsys):
    conn = _fresh_db(tmp_path)
    _add_element(conn, "gen_x", "Икс")
    _add_recipe(conn, "gen_w|gen_x_src", "water", "stone", "gen_x")
    clean_db.cmd_list(conn)
    out = capsys.readouterr().out
    assert "gen_x" in out and "tester" in out
    conn.close()
