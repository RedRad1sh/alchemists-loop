"""T04/T08 (U5) + T29 (I-1): pure-stdlib доказательство атомарности переходов.

БЕЗ fastapi/pytest: обычный sqlite3 + threading. Прогоняется как напрямую
(`python tests/harness_atomicity_u5.py`), так и из-под pytest (функция
`test_atomicity_harness`). Повторяет ровно те SQL-операторы и порядок
транзакций, что использует server.py (_try_acquire_pair_lock /
_release_pair_lock / _ensure_challenge / guarded-переход _score_challenge /
клейм отголосков _claim_echoes), под реальную гонку потоков на файловой
WAL-базе. Копии SQL сверяются с исходником server.py через server_tie.verify
(I-5): рассинхрон — падение.

Ключевые инварианты, которые доказываются:
- сценарии 1-3: НИКОГДА одновременно держателем лока не может быть больше одного
  потока (в т.ч. на Windows, где time.time() квантуется ~15.6 мс и два потока
  получают идентичный now);
- сценарий 4: won перехода цели дня — ровно один;
- сценарий 5 (T29): клейм отголосков одним device_id из N потоков отдаёт эфир
  ровно один раз: сумма claimed == исходный баланс (после T29 HTTP-хендлеры
  пишут в SQLite из threadpool, и «прочитали balance → обнулили» перестало быть
  одним тиком event loop).
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
sys.path.insert(0, HERE)
import server_tie

# I-5: LOCK_TTL и SQL-копии НИЖЕ сверяются с исходником server.py через
# server_tie.verify (import server на голом python невозможен — нет fastapi;
# идёт разбор исходника). Откат/правка сервера роняет харнесс, а не оставляет
# его «сам себе доказательством».
LOCK_TTL = server_tie.lock_ttl()

UPSERT = (
    "INSERT INTO pending_pairs (pair_key, state, lock_ts, owner, attempted_by)"
    " VALUES (?, 'locked', ?, ?, ?)"
    " ON CONFLICT(pair_key) DO UPDATE SET"
    "   state='locked', lock_ts=excluded.lock_ts,"
    "   owner=excluded.owner, attempted_by=excluded.attempted_by"
    " WHERE pending_pairs.state != 'locked' OR pending_pairs.lock_ts <= ?"
)
RELEASE_SQL = ("DELETE FROM pending_pairs"
               " WHERE pair_key = ? AND state = 'locked' AND owner = ?")

# I-2: переход _score_challenge (гард completed_at IS NULL) — та же форма,
# что в server.py; сценарий 4 доказывает «won не больше одного раза».
SCORE_UPSERT = (
    "INSERT INTO challenge_scores (day, device_id, nick, points, first_at, completed_at)"
    " VALUES (?, ?, ?, 1, ?, ?)"
    " ON CONFLICT(day, device_id) DO UPDATE SET"
    "   points = points + 1, nick = excluded.nick, completed_at = excluded.completed_at"
    " WHERE challenge_scores.completed_at IS NULL"
)
SCORE_TOPUP = ("UPDATE challenge_scores SET points = points + 1, nick = ?"
               " WHERE day = ? AND device_id = ?")

# T29 (I-1): копия клейма отголосков (server._echo_row + server._claim_echoes).
# Обнуление баланса условно по прочитанному значению: без `AND balance = ?` два
# потока-писателя (хендлеры после T29 — sync `def`, т.е. threadpool) выдают эфир
# дважды. CLAIM_REREAD — перечитывание total проигравшим (ветка rowcount != 1).
CLAIM_ENSURE = ("INSERT OR IGNORE INTO echoes (device_id, balance, total)"
                " VALUES (?, 0, 0)")
CLAIM_READ = ("SELECT balance, total, last_apprentice_day FROM echoes"
              " WHERE device_id = ?")
CLAIM_UPDATE = ("UPDATE echoes SET balance = 0 WHERE device_id = ? AND balance = ?")
CLAIM_REREAD = "SELECT total FROM echoes WHERE device_id = ?"
# ECHO_ETHER тоже из исходника: копия считает выплату по серверной константе.
ECHO_ETHER = server_tie.echo_ether()

# T09/U8 (d): TOPUP-копия тоже привязана к исходнику — её расхождение с
# server.py роняет харнесс, а не оставляет сценарий 4 с устаревшим UPDATE.
# T29 (I-1) + U25 (re-review #4): привязан весь переход клейма, а не только
# WHERE обнуления — копия читающего запроса (набор полей SELECT из _echo_row)
# могла уехать от сервера молча, а надпись «копия server._echo_row» осталась бы
# правдой наполовину. Правка любого из четырёх запросов роняет verify(), а не
# превращает сценарий 5 в зеркало самого себя.
server_tie.verify(UPSERT, RELEASE_SQL, LOCK_TTL, SCORE_UPSERT, topup_sql=SCORE_TOPUP,
                  claim_copy=(CLAIM_ENSURE, CLAIM_READ, CLAIM_UPDATE, CLAIM_REREAD))


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
    cur = conn.execute(RELEASE_SQL, (pair_key, owner))
    conn.commit()
    return cur.rowcount


def score_challenge(conn, day, device_id, nick, now_iso):
    """Копия scoring-перехода server._score_challenge (I-2): guarded UPSERT
    закрывает completed_at ровно у одного победителя перехода; уже выполненная
    строка → rowcount 0 → только очок. Возвращает won."""
    cur = conn.execute(SCORE_UPSERT, (day, device_id, nick, now_iso, now_iso))
    won = cur.rowcount == 1
    if not won:
        conn.execute(SCORE_TOPUP, (nick, day, device_id))
    conn.commit()
    return won


def echo_row(conn, device_id):
    """Копия server._echo_row: INSERT OR IGNORE + SELECT строки отголосков."""
    conn.execute(CLAIM_ENSURE, (device_id,))
    return conn.execute(CLAIM_READ, (device_id,)).fetchone()


def claim_echoes(conn, device_id, plain_read=False, gate=None):
    """Копия server._claim_echoes (T29 I-1): CAS-обнуление + решение по rowcount.

    plain_read=True — баланс прочитан БЕЗ _echo_row (строка отголосков уже
    есть): SELECT в legacy-режиме python sqlite3 транзакцию не открывает, поэтому
    окно между чтением и списком остаётся открытым — ровно то, что закрывает
    guard в CLAIM_UPDATE. При plain_read=False копия повторяет server.py
    дословно: читающий INSERT OR IGNORE из _echo_row сам открывает write-
    транзакцию, и окно закрывается им (сценарий 5a сторожит этим путь хендлера,
    но guarded/безусловный UPDATE не различает — за этим идёт 5b).

    gate — опциональный barrier: все потоки сошлись на чтении и только потом
    списывают, чтобы окно было открыто ЗАВЕДОМО (иначе на быстрых машинах
    планировщик успевает сериализовать гонку и сценарий стал бы зелёным при
    любом коде). Возвращает (claimed, ether, total)."""
    row = (conn.execute(CLAIM_READ, (device_id,)).fetchone() if plain_read
           else echo_row(conn, device_id))
    balance, total = row["balance"], row["total"]
    if gate is not None:
        gate.wait(timeout=10)
    cur = conn.execute(CLAIM_UPDATE, (device_id, balance))
    conn.commit()
    if cur.rowcount == 1:
        return balance, balance * ECHO_ETHER, total
    loser = conn.execute(CLAIM_REREAD, (device_id,)).fetchone()
    return 0, 0, loser["total"] if loser else 0


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
        доказываемый инвариант (последовательные перезахваты допустимы).
        I-5: окно держателя покрывает и commit релиза — счётчик убирается
        ПОСЛЕ release(), т.е. реальный DB-visible интервал владения лока."""
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
                rel = release(cc, pk, tag)
                with jlock:
                    stats["holders"] -= 1
                assert rel == 1, "освобождение своего лока по токену"
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

    # 4) I-2: гонка scoring'а цели дня одним устройством — won не больше одного
    #    раза и без IntegrityError. 4a) легаси-строка completed_at IS NULL
    #    (наследие vein-канала до разнесения), 4b) строки вовсе нет.
    def tap(day, device, out_list):
        try:
            cc = _db_conn(db)
            w = score_challenge(cc, day, device, "Алик", "now")
            with jlock:
                out_list.append(w)
            cc.close()
        except Exception:
            with jlock:
                errors.append(traceback.format_exc())

    conn = _db_conn(db)
    conn.execute("INSERT INTO challenge_scores (day, device_id, nick, points, first_at, completed_at)"
                 " VALUES ('2031-01-01','dev-1','Алик',3,'earlier',NULL)")
    conn.commit()
    conn.close()
    wins_legacy = []
    ths = [threading.Thread(target=tap, args=("2031-01-01", "dev-1", wins_legacy)) for _ in range(8)]
    [t.start() for t in ths]
    [t.join() for t in ths]
    conn = _db_conn(db)
    r = conn.execute("SELECT points, completed_at FROM challenge_scores"
                     " WHERE day='2031-01-01' AND device_id='dev-1'").fetchone()
    assert sum(wins_legacy) == 1, "на легаси-строке won ровно одному переходу"
    assert r["points"] == 3 + 8 and r["completed_at"] == "now", \
        "очки посчитаны всеми, completed_at закрыт победителем"

    wins_new = []
    ths = [threading.Thread(target=tap, args=("2031-01-02", "dev-2", wins_new)) for _ in range(8)]
    [t.start() for t in ths]
    [t.join() for t in ths]
    r2 = conn.execute("SELECT points, completed_at FROM challenge_scores"
                      " WHERE day='2031-01-02' AND device_id='dev-2'").fetchone()
    conn.close()
    assert sum(wins_new) == 1, "создание строки с won — ровно один раз (нет двойного won/500)"
    assert r2["points"] == 8 and r2["completed_at"] == "now"
    say("round4 (_score_challenge гонка x8): won на легаси =", sum(wins_legacy),
        "| won на новой =", sum(wins_new), "| ошибок =", len(errors))
    assert not errors

    # 5) T29 (I-1): гонка клейма отголосков ОДНИМ устройством из N потоков.
    #    Инвариант: сумма claimed по потокам == исходный баланс, победитель ровно
    #    один, вечный total не меняется. После перевода echoes_claim на sync `def`
    #    (threadpool) «прочитали balance → обнулили» — это уже не один тик event
    #    loop, поэтому без guard два потока отдали бы эфир дважды.
    #    5a — путь хендлера дословно (_echo_row + CAS);
    #    5b — то же списание, но баланс прочитан отдельной транзакцией и потоки
    #        сошлись на барьере: окно «прочитали → списали» открыто ЗАВЕДОМО.
    #    РАЗЛИЧНИК (мутация, которая красит 5b): сделать предикат guard'а
    #    тавтологией, сохранив арность биндингов (`AND balance = ?` → например
    #    `AND ? IS NOT NULL`) — каждый из 8 потоков заберёт свои 100,
    #    sum(claimed) = 800 != 100, assert ниже падает. (Буквальное удаление
    #    `AND balance = ?` красит тот же сценарий другой причиной: параметр
    #    остаётся в биндингах и sqlite3 падает на ProgrammingError.) Под той
    #    же мутацией 5a ОСТАЁТСЯ зелёным: там чтением заведомо владеет write-
    #    транзакция, открытая INSERT OR IGNORE из _echo_row (наблюдение на этой
    #    коробке, sqlite 3.41.2) — поэтому 5a сторожит путь хендлера от регресса
    #    «потеряли деньги», а guarded/безусловный различает именно 5b.
    #    Правка guard'а в server.py роняет ещё и server_tie.verify (CLAIM WHERE),
    #    т.е. краснеют обе проверки, а не только зеркало харнесса.
    START = 100
    TOTAL0 = 250  # вечный счётчик: клейм обязан оставить как есть

    def seed_echo(device, balance, total):
        cc = _db_conn(db)
        cc.execute("INSERT OR REPLACE INTO echoes (device_id, balance, total)"
                   " VALUES (?, ?, ?)", (device, balance, total))
        cc.commit()
        cc.close()

    def claim_one(device, plain, gate, out):
        try:
            cc = _db_conn(db)
            got = claim_echoes(cc, device, plain_read=plain, gate=gate)
            with jlock:
                out.append(got)
            cc.close()
        except Exception:
            with jlock:
                errors.append(traceback.format_exc())

    def claim_race(n, plain, device):
        out = []
        # барьер только для 5b: он обязан сойтись НА ЧТЕНИИ, иначе окно гонки
        # закрыто не guard'ом, а порядком запуска потоков
        gate = threading.Barrier(n) if plain else None
        ths = [threading.Thread(target=claim_one, args=(device, plain, gate, out))
               for _ in range(n)]
        [t.start() for t in ths]
        [t.join(timeout=20) for t in ths]
        return out

    def check_claim_round(label, device, plain):
        seed_echo(device, START, TOTAL0)
        got = claim_race(8, plain, device)
        assert len(got) == 8, "все 8 потоков вернули ответ: %s" % got
        claimed = sum(c for c, _e, _t in got)
        winners = [c for c, _e, _t in got if c]
        cc = _db_conn(db)
        row = cc.execute("SELECT balance, total FROM echoes WHERE device_id = ?",
                         (device,)).fetchone()
        cc.close()
        say("%s (x8 потоков на device_id=%s): сумма claimed = %d, победителей = %d, "
            "баланс после = %d, total после = %d, ошибок = %d"
            % (label, device, claimed, len(winners), row["balance"], row["total"],
               len(errors)))
        # ДВОЙНАЯ ВЫДАЧА: вот где краснеет unconditional UPDATE (сумма больше
        # баланса) и вот где краснеет любой регресс guard'а.
        assert claimed == START, (
            "%s: сумма claimed (%d) != исходный баланс (%d) — эфир выдан дважды "
            "или потерян; guard `AND balance = ?` в _claim_echoes больше не "
            "сериализует клейм" % (label, claimed, START))
        assert len(winners) == 1, "%s: победитель обязан быть ровно один" % label
        assert all(e == c * ECHO_ETHER for c, e, _t in got), \
            "эфир = claimed * ECHO_ETHER (константа из server.py)"
        assert row["balance"] == 0 and row["total"] == TOTAL0, \
            "баланс обнулён, вечный счётчик не тронут"
        # повторный тап после гонки — честно 0 (строка цела, значению некуда «потеряться»)
        cc = _db_conn(db)
        again = claim_echoes(cc, device)
        cc.close()
        assert again == (0, 0, TOTAL0), "повторный клейм пустого баланса: %s" % (again,)

    check_claim_round("round5a (_claim_echoes путь хендлера)", "dev-h5a", plain=False)
    check_claim_round("round5b (чтение отдельной транзакцией + CAS)", "dev-h5b", plain=True)
    # поведение, обязательное к сохранению (tests/test_v24_resonance.py:294):
    # неизвестное устройство = 0 без падения
    cc = _db_conn(db)
    unknown = claim_echoes(cc, "dev-h5-unknown")
    created = cc.execute("SELECT COUNT(*) c FROM echoes WHERE device_id = 'dev-h5-unknown'"
                         ).fetchone()["c"]
    cc.close()
    say("round5c (неизвестное устройство): ответ =", unknown, "| строка создана =", created)
    assert unknown == (0, 0, 0) and created == 1, \
        "новое устройство: ok=True, claimed=0, строка создана _echo_row"
    assert not errors
    say("HARNESS OK")


def test_atomicity_harness():
    _run_harness(verbose=False)


if __name__ == "__main__":
    _run_harness(verbose=True)
