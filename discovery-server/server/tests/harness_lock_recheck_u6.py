"""U6/T05 (U5-review fix (a)): post-lock double-check + owner-токен лока.

БЕЗ fastapi/pytest: обычный sqlite3. Повторяет ровно тот порядок операторов,
что /api/discover в server.py: pre-lock проверка → guarded-UPSERT захват →
POST-LOCK RE-CHECK (recipes/rejected_pairs) → «генерация» (счётчик LLM-вызовов)
→ материализация → release по owner-токену.

Доказываемые инварианты:
1. Воришка протухшего лока, у которого предыдущий держатель УСПЕЛ
   материализовать пару, НЕ платит второй вызов LLM: gen_calls == 1,
   и освобождение идёт по своему токену (чужой лок не стирается).
2. release по неверному owner не удаляет строк (защита от «проигравший
   смахнул живой лок» при рефакторинге).
3. Протухший НЕ-материализованный лок (дед держателя) — воришка честно
   генерирует ОДИН раз и сам освобождает.

Прогон: python tests/harness_lock_recheck_u6.py (или из-под pytest).
"""
import os
import sqlite3
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(HERE, "..", "schema.sql")
# Число должно совпадать с server.LOCK_TTL (U5-fix: >= 3 attempts x 30s).
LOCK_TTL = 120.0

ACQUIRE_SQL = (
    "INSERT INTO pending_pairs (pair_key, state, lock_ts, owner, attempted_by)"
    " VALUES (?, 'locked', ?, ?, ?)"
    " ON CONFLICT(pair_key) DO UPDATE SET"
    "   state='locked', lock_ts=excluded.lock_ts,"
    "   owner=excluded.owner, attempted_by=excluded.attempted_by"
    " WHERE pending_pairs.state != 'locked' OR pending_pairs.lock_ts <= ?"
)
RELEASE_SQL = ("DELETE FROM pending_pairs"
               " WHERE pair_key = ? AND state = 'locked' AND owner = ?")


def _db_conn(db):
    conn = sqlite3.connect(db, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


# --- копии операторов server.py --------------------------------------------

def acquire(conn, pair_key, owner, attempted_by, now):
    conn.execute("BEGIN IMMEDIATE")
    try:
        cur = conn.execute(ACQUIRE_SQL, (pair_key, now, owner, attempted_by, now - LOCK_TTL))
        grabbed = cur.rowcount == 1
        conn.commit()
        return grabbed
    except Exception:
        conn.rollback()
        raise


def release(conn, pair_key, owner):
    cur = conn.execute(RELEASE_SQL, (pair_key, owner))
    conn.commit()
    return cur.rowcount


def existing_pair(conn, pair_key):
    """Копия server._existing_pair_response (без резонанса — он не про LLM)."""
    if conn.execute("SELECT 1 FROM recipes WHERE pair_key = ?", (pair_key,)).fetchone():
        return "known"
    if conn.execute("SELECT 1 FROM rejected_pairs WHERE pair_key = ?", (pair_key,)).fetchone():
        return "not_combinable"
    return None


def materialize(conn, pair_key):
    """Копия «создал элемент + рецепт» (для счёчика LLM — обёртка вызова)."""
    stats["gen_calls"] += 1
    cur = conn.execute(
        "INSERT INTO elements (slug, name, name_norm, color, layer, category, author)"
        " VALUES (?, ?, ?, '#fff', 2, 'stone', 'автор')",
        (f"gen-{stats['gen_calls']}", f"Вещ-{stats['gen_calls']}", f"вещ-{stats['gen_calls']}"),
    )
    conn.execute(
        "INSERT INTO recipes (pair_key, a, b, out_id, discoverer) VALUES (?, 'fire', 'gold', ?, 'автор')",
        (pair_key, cur.lastrowid),
    )
    conn.commit()


def discover_flow(conn, pair_key, token, nick, now):
    """Порядок шагов /api/discover: pre-check → захват → RE-CHECK → генерация."""
    if existing_pair(conn, pair_key):
        return "existing(pre-lock)"
    if not acquire(conn, pair_key, token, nick, now):
        return "busy-409"
    try:
        if existing_pair(conn, pair_key):        # ← U5-fix (a): post-lock double-check
            return "existing(post-lock)"
        materialize(conn, pair_key)
        return "generated"
    finally:
        release(conn, pair_key, token)


def _run(verbose=True):
    def say(*a):
        if verbose:
            print(*a)

    global stats
    tmpdir = tempfile.mkdtemp(prefix="u6_harness_")
    db = os.path.join(tmpdir, "harness.db")
    conn = _db_conn(db)
    with open(SCHEMA, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.commit()
    stats = {"gen_calls": 0}

    # 1) ХУЖШИЙ СЦЕНАРИЙ review (a): держатель с лока-«трупом» после
    #    материализации (умер до release; лок протух). Воришка обязан
    #    НЕ заплатить LLM за уже готовую пару.
    pk = "fire|gold"
    assert acquire(conn, pk, "tok-crash", "сбойщик", time.time() - LOCK_TTL - 1) is True
    materialize(conn, pk)                       # предыдущий держатель УСПЕЛ создать
    assert stats["gen_calls"] == 1
    t = discover_flow(conn, pk, "tok-thief", "воришка", time.time())
    say("сценарий 1 (материализовано под протухшим лока):", t, "| LLM-вызовов =", stats["gen_calls"])
    assert t.startswith("existing") and stats["gen_calls"] == 1
    # и тот же воришка, дошедший до захвата (pre-check ослеп интерливингом —
    # см. сценарий 1b): кража протухшего лока, post-lock re-check, свой release
    assert acquire(conn, pk, "tok-thief2", "воришка2", time.time()) is True, \
        "протухший лок перезахватываем"
    assert existing_pair(conn, pk) == "known", "re-check после захвата ловит готовую пару"
    assert release(conn, pk, "tok-thief2") == 1
    assert conn.execute("SELECT COUNT(*) c FROM pending_pairs").fetchone()["c"] == 0, \
        "воришка снял СВОЙ (перезахваченный) лок"
    assert stats["gen_calls"] == 1, "ни одного лишнего LLM-вызова"

    # 1b) Та же пара, но pre-check «ослепл» (симулируем интерливинг: запись
    #     появилась МЕЖДУ pre-check и re-check воришки — re-check ловит).
    conn.execute("DELETE FROM recipes WHERE pair_key = ?", (pk,))
    conn.execute("DELETE FROM elements")
    conn.commit()
    calls0 = stats["gen_calls"]
    got = acquire(conn, pk, "tok-A", "A", time.time())            # A держит живой лок
    assert got
    # B пришёл «раньше» — pre-check пуст; затем A материализует и НЕ релизнул
    # к моменту, когда лок A протух (сдвигаем lock_ts назад, как время гонки).
    assert existing_pair(conn, pk) is None                        # pre-check B: пусто
    materialize(conn, pk)                                          # A успел (LLM #2)
    conn.execute("UPDATE pending_pairs SET lock_ts = ? WHERE pair_key = ?",
                 (time.time() - LOCK_TTL - 1, pk))                 # лок A протух
    conn.commit()
    assert acquire(conn, pk, "tok-B", "B", time.time()) is True   # B украл протухший лок
    assert existing_pair(conn, pk) == "known"                      # RE-CHECK B: не генерируем
    assert release(conn, pk, "tok-B") == 1
    say("сценарий 1b (интерливинг pre/re-check): LLM-вызовов =", stats["gen_calls"] - calls0)
    assert stats["gen_calls"] - calls0 == 1, "только A заплатил за генерацию"

    # 2) release по чужому токену — ноль строк (проигравший не трёт живой лок)
    assert acquire(conn, "a|b", "tok-live", "живой", time.time()) is True
    assert release(conn, "a|b", "tok-чужак") == 0
    assert release(conn, "a|b", "tok-live") == 1

    # 3) Честный протухший лок без материализации (dead держатель): воришка
    #    генерирует РОВНО один раз и сам освобождает.
    pk3 = "water|salt"
    assert acquire(conn, pk3, "tok-dead", "мертвец", time.time() - LOCK_TTL - 1) is True
    calls1 = stats["gen_calls"]
    r3 = discover_flow(conn, pk3, "tok-new", "новый", time.time())
    say("сценарий 3 (протухший без записи):", r3, "| LLM-вызовов =", stats["gen_calls"] - calls1)
    assert r3 == "generated" and stats["gen_calls"] - calls1 == 1
    assert conn.execute("SELECT COUNT(*) c FROM pending_pairs").fetchone()["c"] == 0

    conn.close()
    say("HARNESS U6 OK")


def test_lock_recheck_harness():
    _run(verbose=False)


if __name__ == "__main__":
    _run()
