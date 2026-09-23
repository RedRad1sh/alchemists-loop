"""T04/T08 (U5): pure-stdlib доказательство атомарности pending_pairs/challenge.

БЕЗ fastapi/pytest: обычный sqlite3 + threading. Прогоняется как напрямую
(`python tests/harness_atomicity_u5.py`), так и из-под pytest (функция
`test_atomicity_harness`). Повторяет ровно те SQL-операторы и порядок
транзакций, что использует server.py (_try_acquire_pair_lock /
_release_pair_lock / _ensure_challenge), под реальную гонку потоков на
файловой WAL-базе.

Ключевой инвариант, который доказывается: НИКОГДА одновременно держателем
лока не может быть больше одного потока (в т.ч. на Windows, где time.time()
квантуется ~15.6 мс и два потоков получают идентичный now).
"""
import os
import sqlite3
import sys
import tempfile
import threading
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(HERE, "..", "schema.sql")
LOCK_TTL = 120.0  # секунд; то же значение, что в server.py (U5-fix: >= худшего окна генерации)

UPSERT = (
    "INSERT INTO pending_pairs (pair_key, state, lock_ts, owner, attempted_by)"
    " VALUES (?, 'locked', ?, ?, ?)"
    " ON CONFLICT(pair_key) DO UPDATE SET"
    "   state='locked', lock_ts=excluded.lock_ts,"
    "   owner=excluded.owner, attempted_by=excluded.attempted_by"
    " WHERE pending_pairs.state != 'locked' OR pending_pairs.lock_ts <= ?"
)


def _db_conn(db):
    conn = sqlite3.connect(db, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


# --- копии операторов server.py -------------------------------------------

def acquire(conn, pair_key, owner, attempted_by, now):
    """Копия server._try_acquire_pair_lock: BEGIN IMMEDIATE + guarded UPSERT.
    owner — уникальный токен захвата (в проде uuid4.hex)."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        cur = conn.execute(UPSERT, (pair_key, now, owner, attempted_by, now - LOCK_TTL))
        grabbed = cur.rowcount == 1
        conn.commit()
        return grabbed
    except Exception:
        conn.rollback()
        raise


def release(conn, pair_key, owner):
    """Копия server._release_pair_lock: DELETE, привязанный к токену СВОЕГО
    захвата (U5-fix): чужой лок не смахнёт, даже если lock_ts совпали."""
    cur = conn.execute(
        "DELETE FROM pending_pairs WHERE pair_key = ? AND state = 'locked' AND owner = ?",
        (pair_key, owner),
    )
    conn.commit()
    return cur.rowcount


def _run_harness(verbose=True):
    def say(*a):
        if verbose:
            print(*a)

    tmpdir = tempfile.mkdtemp(prefix="u5_harness_")
    db = os.path.join(tmpdir, "harness.db")
    conn = _db_conn(db)
    with open(SCHEMA, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.commit()
    say("python:", sys.version.split()[0], "| sqlite:", sqlite3.sqlite_version)

    # 0) rowcount-семантика вне гонки (на ней держится захват)
    assert acquire(conn, "t|one", "u1", "u1", time.time()) is True
    assert acquire(conn, "t|one", "u2", "u2", time.time()) is False, "живой лок: отказ"
    # освобождение — только по своему токену: чужой лок не смахивается
    assert release(conn, "t|one", "u2") == 0, "проигравший не снимает чужой лок"
    assert release(conn, "t|one", "u1") == 1
    cur = conn.execute("INSERT OR IGNORE INTO challenges (day,target,target_name,hint,created_at)"
                       " VALUES ('2000-01-01','fire','Огонь','h','now')")
    conn.commit()
    assert cur.rowcount == 1
    cur = conn.execute("INSERT OR IGNORE INTO challenges (day,target,target_name,hint,created_at)"
                       " VALUES ('2000-01-01','gold','Золото','h','now')")
    conn.commit()
    assert cur.rowcount == 0, "INSERT OR IGNORE дубля: rowcount 0"
    say("rowcount-семантика: guarded UPSERT 1/0, OR IGNORE 1/0 — подтверждено")
    conn.close()

    pk = "fire|gold"
    errors = []
    jlock = threading.Lock()

    def racer(tag, stats, hold):
        """Каждый поток: захватить; если удалось — подержать «генерацию» и
        освободить. stats считает ПИК одновременных держателей — это и есть
        доказываемый инвариант (последовательные перезахваты допустимы)."""
        try:
            cc = _db_conn(db)
            now = time.time()
            if acquire(cc, pk, tag, tag, now):
                with jlock:
                    stats["holders"] += 1
                    stats["peak"] = max(stats["peak"], stats["holders"])
                    stats["wins"].append(tag)
                if hold:
                    time.sleep(0.3)  # имитация LLM-генерации под локастом
                with jlock:
                    stats["holders"] -= 1
                    stats["declines"] += 0
                assert release(cc, pk, tag) == 1, "освобождение своего лока по токену"
            else:
                with jlock:
                    stats["declines"] += 1
            cc.close()
        except Exception:
            with jlock:
                errors.append(traceback.format_exc())

    def race(n, hold=True):
        stats = {"holders": 0, "peak": 0, "wins": [], "declines": 0}
        ths = [threading.Thread(target=racer, args=(f"u{i}", stats, hold)) for i in range(n)]
        [t.start() for t in ths]
        [t.join() for t in ths]
        return stats

    # 1) 16 потоков на новую пару — пик одновременных держателей == 1
    s1 = race(16)
    say("round1 (гонка 16 потоков): побед всего =", len(s1["wins"]),
        "отказов при живом локе =", s1["declines"], "| ПИК держателей =", s1["peak"],
        "| ошибок =", len(errors))
    assert s1["peak"] == 1 and s1["declines"] > 0 and not errors

    # 2) протухший лок (сбой держателя) — перезахват также не более одного
    cc = _db_conn(db)
    assert acquire(cc, pk, "stale", "stale", time.time() - LOCK_TTL - 5) is True
    cc.close()
    s2 = race(8)
    say("round2 (протухший лок): побед всего =", len(s2["wins"]),
        "| ПИК держателей =", s2["peak"], "| ошибок =", len(errors))
    assert s2["peak"] == 1 and not errors

    # 3) challenges: 12 потоков вставляют один день — без IntegrityError, 1 строка
    def ensure_challenge():
        try:
            cc = _db_conn(db)
            # копия server._ensure_challenge: OR IGNORE, commit, re-SELECT
            cc.execute("INSERT OR IGNORE INTO challenges (day,target,target_name,hint,created_at)"
                       " VALUES ('2030-12-31','fire','Огонь','h','now')")
            cc.commit()
            assert cc.execute("SELECT 1 FROM challenges WHERE day='2030-12-31'").fetchone()
            cc.close()
        except Exception:
            with jlock:
                errors.append(traceback.format_exc())

    ths = [threading.Thread(target=ensure_challenge) for _ in range(12)]
    [t.start() for t in ths]
    [t.join() for t in ths]
    conn = _db_conn(db)
    n = conn.execute("SELECT COUNT(*) c FROM challenges WHERE day='2030-12-31'").fetchone()["c"]
    left = conn.execute("SELECT COUNT(*) c FROM pending_pairs").fetchone()["c"]
    conn.close()
    say("round3 (_ensure_challenge x12): строк за день =", n, "| ошибок =", len(errors))
    say("pending_pairs после всех раундов:", left, "(resolved-«могилы» не копятся)")
    assert n == 1 and left == 0 and not errors
    say("HARNESS OK")


def test_atomicity_harness():
    _run_harness(verbose=False)


if __name__ == "__main__":
    _run_harness(verbose=True)
