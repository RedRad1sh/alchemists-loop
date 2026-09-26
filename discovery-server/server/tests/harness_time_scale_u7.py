# -*- coding: utf-8 -*-
"""U7/T06: единая временная шкала сервера (UTC + фиксированный DAY_TZ_OFFSET).

БЕЗ fastapi/pytest: обычный sqlite3. import server на голом python невозможен
(fastapi нет, gen_llm — 3.10-синтаксис), поэтому хелперы времени server.py
ВЫРЕЗАЮТСЯ из исходника и исполняются exec'ом (тот же приём, что server_tie
для SQL-копий), а «сейчас» подставляется закреплённым stub'ом datetime.now.
Честность (откат унификации роняет харнесс ГРОМКО):
- stub datetime.now() требует tz=timezone.utc — возврат к naive-локальному
  datetime.now() или date.today() даёт падение;
- audit- проверки исходника: в server.py не осталось date('now') в SQL,
  .timestamp() вне комментариев, _today/_week_key/эндпоинты идут через _now_dt.

Доказываемые инварианты (Verification из T06):
1. При DAY_TZ_OFFSET=+03:00 цель дня, окно ярмарки (last_seen) и лента
   today_events МЕНЯЮТ ДАТУ В ОДИН МОМЕНТ: на инстантах «до»/«после»
   21:00 UTC (полночь МСК) все ключи переходят D -> D+1 одновременно,
   хотя UTC-дата за инстантом ещё прежняя (граница НЕ на полуночи UTC).
2. При смещении по умолчанию (0) ключ дня == UTC-дата и переворачивается
   ровно на границе UTC-суток.
3. SQL-запрос ленты/ярмарки — ВЫРЕЗАННЫЕ ИЗ SERVER.py тексты, прогнанные
   по реальной sqlite: stored created_at (isoformat) и last_seen корректно
   считаются тем же ключом _today().
4. Парсер DAY_TZ_OFFSET: '+03:00'/-4/+0530/пусто — ок; мусор — ValueError.

Прогон: python tests/harness_time_scale_u7.py (или из-под pytest:
test_time_scale_harness).
"""
import hashlib
import os
import re
import sqlite3
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_PY = os.path.abspath(os.path.join(HERE, "..", "server.py"))
SCHEMA = os.path.join(HERE, "..", "schema.sql")


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _section(src, fn):
    """Тело функции fn из исходника (от def до следующего def верхнего уровня)."""
    i = src.index("def %s(" % fn)
    j = src.find("\ndef ", i + 1)
    return src[i:j if j != -1 else len(src)]


class _StubDatetime:
    """datetime.now(tz) только из UTC: закреплённый инстант. Откат хелперов
    к локальному времени падает здесь же (tz=None или не-UTC)."""
    instant = None

    @classmethod
    def now(cls, tz=None):
        if tz is not timezone.utc:
            raise AssertionError(
                "T06 DRIFT: серверная «сейчас» берётся не из datetime.now(timezone.utc) "
                "(tz=%r) — шкала разъехалась" % (tz,))
        return cls.instant


def _extract_helpers(src):
    """exec-вырезка блока времени из server.py: парсер смещения + хелперы."""
    start = src.index("def _parse_day_tz_offset")
    end = src.index("ECHO_ETHER")  # конец блока конфигурации времени
    ns = {
        "re": re, "os": os, "timedelta": timedelta, "timezone": timezone,
        "date": date, "datetime": _StubDatetime,
        "environ": {},  # os.environ в скоупе не нужен: константу перезапишем
    }
    exec(compile(src[start:end], "server.py<time-block>", "exec"), ns)
    for fn in ("_parse_day_tz_offset", "_now_dt", "_now_iso", "_today", "_today_date",
               "DAY_TZ_OFFSET_SEC"):
        if fn not in ns:
            raise AssertionError("T06 DRIFT: хелпер %s не найден в блоке времени server.py" % fn)
    # _challenge_target_for — «цель дня» берётся из этого же дня-ключа:
    m = re.search(r"CHALLENGE_TARGETS = \[(.*?)\]", src, re.S)
    targets = eval("[" + m.group(1) + "]")  # noqa: S307 — литерал из исходника
    ch_ns = {"hashlib": hashlib, "CHALLENGE_TARGETS": targets}
    exec(compile(_section(src, "_challenge_target_for"), "server.py<challenge>", "exec"), ch_ns)
    return ns, ch_ns["_challenge_target_for"]


# --- аудит исходника (откат унификации роняет харнесс) ---------------------

def _audit_source(src):
    def strip_comments(text):
        out = []
        for line in text.splitlines():
            if line.strip().startswith("#"):
                continue
            out.append(line)
        return "\n".join(out)

    code = strip_comments(src)
    if "date('now')" in code:
        raise AssertionError("T06 DRIFT: в SQL server.py снова появился SQLite date('now')")
    for m in re.finditer(r"datetime\('now'\)", code):
        line = next(l for l in code.splitlines() if m.group(0) in l)
        if "DEFAULT (datetime('now'))" not in line:
            raise AssertionError(
                "T06 DRIFT: datetime('now') вне DDL-дефолта (audit-колонки): %s" % line.strip())
    calls = re.findall(r"datetime\.now\((.*?)\)", code)
    if len(calls) != 1 or "timezone.utc" not in calls[0]:
        raise AssertionError(
            "T06 DRIFT: datetime.now() вне _now_dt (единственный вызов с timezone.utc): %r" % (calls,))
    if re.search(r"(?<!_)\bdate\.today\(\)|_date\.today\(\)", code):
        raise AssertionError("T06 DRIFT: локальная date.today() вернулась в код server.py")
    if ".timestamp()" in code:
        raise AssertionError("T06 DRIFT: .timestamp() (loкал-трактовка naive) вернулся в server.py")
    if "day = _today()" not in _section(src, "_ensure_challenge"):
        raise AssertionError("T06 DRIFT: _ensure_challenge больше не использует _today()")
    if "_now_iso()" not in _section(src, "_score_challenge"):
        raise AssertionError("T06 DRIFT: _score_challenge пишет first_at/completed_at не из _now_iso()")
    if "_today()" not in _section(src, "_upsert_player"):
        raise AssertionError("T06 DRIFT: last_seen в _upsert_player пишется не через _today()")
    if "def _today() -> str" not in src or "_now_dt()" not in _section(src, "_today"):
        raise AssertionError("T06 DRIFT: _today() больше не выводится из _now_dt() — общего источника нет")
    # Недельный ключ харнесс считает сам (см. keys_at): exec-вырезка блока
    # времени не дотягивает до _week_key, поэтому связываем формат исходником.
    if 'f"{iso[0]}-W{iso[1]:02d}"' not in _section(src, "_week_key"):
        raise AssertionError(
            "T06 DRIFT: формат _week_key изменён — keys_at в харнессе зеркалит старый")


# --- SQL-копии, вырезанные из server.py ------------------------------------

def _extract_sql(src):
    feed = re.search(r'"SELECT COUNT\(\*\) AS c FROM world_events WHERE date\(created_at\) = \?"', src)
    seen = re.search(r'"UPDATE players SET last_seen = \? WHERE device_id = \?"', src)
    active7 = re.search(r'"SELECT COUNT\(\*\) AS c FROM players WHERE last_seen IS NOT NULL AND last_seen >= date\(\?\)"', src)
    insert_p = re.search(r'"INSERT INTO players \(nick, device_id, last_seen, created_at\) VALUES \(\?, \?, \?, \?\)"', src)
    for label, m in (("today_events", feed), ("last_seen UPDATE", seen),
                     ("активное окно ярмарки", active7), ("INSERT players", insert_p)):
        if not m:
            raise AssertionError(
                "T06 DRIFT: SQL '%s' больше не найдено в исходнике server.py — "
                "харнесс зеркалил бы не сервер" % label)
    return tuple(m.group(0).strip('"') for m in (feed, seen, active7, insert_p))


def _db(tmpdir):
    conn = sqlite3.connect(os.path.join(tmpdir, "u7.db"), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    with open(SCHEMA, encoding="utf-8") as f:
        conn.executescript(f.read())
    return conn


def _scenario(nsc, ch_target, conn, sql, offset_sec, i_before, i_after, say):
    """Один сценарий: до/после границы — все фичи меняют дату вместе."""
    feed_sql, seen_sql, active_sql, insert_sql = sql
    nsc["DAY_TZ_OFFSET_SEC"] = offset_sec

    def keys_at(instant):
        _StubDatetime.instant = instant
        day = nsc["_today"]()
        week = "%04d-W%02d" % tuple(nsc["_today_date"]().isocalendar()[:2])
        return day, week

    day_a, week_a = keys_at(i_before)
    # «записали в момент до границы» — теми же SQL, что использует сервер:
    conn.execute(insert_sql, ("u7-игрок", "dev-1", nsc["_today"](), nsc["_now_iso"]()))
    conn.execute(
        "INSERT INTO world_events (pair_key, a, b, out, out_name, discoverer, created_at)"
        " VALUES ('fire|gold', 'fire', 'gold', 'opal', 'Опал', 'u7-игрок', ?)",
        (nsc["_now_iso"](),),
    )
    conn.commit()
    feed_today_a = conn.execute(feed_sql, (nsc["_today"](),)).fetchone()["c"]
    since_a = (nsc["_today_date"]() - timedelta(days=nsc["_today_date"]().weekday() + 6)).isoformat()
    active_a = conn.execute(active_sql, (since_a,)).fetchone()["c"]
    target_a = ch_target(day_a)
    seen_day_a = conn.execute("SELECT last_seen FROM players WHERE device_id='dev-1'").fetchone()["last_seen"]

    day_b, week_b = keys_at(i_after)
    feed_today_b = conn.execute(feed_sql, (nsc["_today"](),)).fetchone()["c"]
    target_b = ch_target(day_b)
    # игрок «зашёл» после границы: last_seen перезаписывается новым ключом
    conn.execute(seen_sql, (nsc["_today"](), "dev-1"))
    conn.commit()
    seen_day_b = conn.execute("SELECT last_seen FROM players WHERE device_id='dev-1'").fetchone()["last_seen"]

    # 1) ВСЕ ключи фич на одном инстанте — один и тот же день (общий _today):
    assert seen_day_a == day_a and feed_today_a == 1 and active_a == 1, \
        "до границы: цель/лента/ярмарка живут днём %s" % day_a
    assert day_b == (datetime.fromisoformat(day_a) + timedelta(days=1)).date().isoformat(), \
        "после границы серверный день ровно +1 (одна инвертированная дата)"
    # 2) ONE-FLIP: лента, цель и last_seen перевернулись на ОДНОМ инстанте:
    assert feed_today_b == 0, "вчера-событие больше не 'today' — лента перевернулась"
    # T09/U8 (a): раньше здесь было `target_b != target_a or day_b != day_a` —
    # ТАВТОЛОГИЯ (day_b != day_a гарантировано выше), проверка ничего не
    # ассертила. Явно: цель — чистая функция серверного дня-ключа, и на
    # переходе границы она перевернулась вместе со всеми (23-е: ice → 24-е: boat).
    assert target_a == ch_target(day_a) and target_b == ch_target(day_b), \
        "цель дня считается ровно из того же серверного дня-ключа"
    assert target_b != target_a, \
        "смена серверного дня переворачивает и цель (one-flip, без дрейфа)"
    assert seen_day_b == day_b != seen_day_a, "окно ярмарки (last_seen) перешло день вместе со всеми"
    assert week_a == week_b or datetime.fromisoformat(day_b).weekday() == 0, \
        "недельный ключ из той же даты"
    say("  до:  day=%s target=%-8s feed=%d active7=%d" % (day_a, target_a, feed_today_a, active_a))
    say("  после: day=%s target=%-8s feed=%d last_seen=%s" % (day_b, target_b, feed_today_b, seen_day_b))
    return day_a, day_b


def _run(verbose=True):
    def say(*a):
        if verbose:
            print(*a)

    src = _read(SERVER_PY)
    _audit_source(src)
    sql = _extract_sql(src)
    nsc, ch_target = _extract_helpers(src)

    # 4) парсер смещения
    p = nsc["_parse_day_tz_offset"]
    assert p("") == 0 and p("0") == 0 and p("+0") == 0
    assert p("+03:00") == 3 * 3600 and p("-4") == -4 * 3600 and p("+0530") == 5 * 3600 + 1800
    for bad in ("+3:60", "msk", "3", "+15:00", "garbage"):
        try:
            p(bad)
        except ValueError:
            pass
        else:
            raise AssertionError("парсер принял мусор: %r" % bad)
    say("парсер DAY_TZ_OFFSET: '+03:00'->10800, '-4'->-14400, мусор -> ValueError")

    tmpdir = tempfile.mkdtemp(prefix="u7_harness_")
    conn = _db(tmpdir)

    # 1) МСК (+03:00): граница дня — 21:00 UTC, а НЕ полночь UTC.
    #    2026-09-23(ср) 20:59:59Z -> МСК 23:59:59 (день 23-е);
    #    2026-09-23(ср) 21:00:01Z -> МСК 00:00:01 (день 24-е), UTC ещё 23-е.
    say("сценарий MSK: DAY_TZ_OFFSET=+03:00, граница 21:00 UTC")
    day_a, day_b = _scenario(
        nsc, ch_target, conn, sql, 3 * 3600,
        datetime(2026, 9, 23, 20, 59, 59, tzinfo=timezone.utc).replace(tzinfo=None),
        datetime(2026, 9, 23, 21, 0, 1, tzinfo=timezone.utc).replace(tzinfo=None), say)
    assert (day_a, day_b) == ("2026-09-23", "2026-09-24")
    # UTC-дата «после» ещё старая — значит флиш НЕ на полуночи UTC, а на МСК:
    assert datetime(2026, 9, 23, 21, 0, 1).strftime("%Y-%m-%d") == "2026-09-23"

    # 2) UTC по умолчанию (смещение 0): ключ == UTC-дата, граница — полночь UTC.
    say("сценарий UTC: смещение по умолчанию (0), граница 00:00 UTC")
    conn.execute("DELETE FROM world_events")
    conn.execute("DELETE FROM players")
    conn.commit()
    day_a, day_b = _scenario(
        nsc, ch_target, conn, sql, 0,
        datetime(2026, 9, 23, 23, 59, 59, tzinfo=timezone.utc).replace(tzinfo=None),
        datetime(2026, 9, 24, 0, 0, 1, tzinfo=timezone.utc).replace(tzinfo=None), say)
    assert (day_a, day_b) == ("2026-09-23", "2026-09-24")

    conn.close()
    say("HARNESS U7 OK")


def test_time_scale_harness():
    _run(verbose=False)


if __name__ == "__main__":
    _run()
