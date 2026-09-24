# -*- coding: utf-8 -*-
"""U6-fix (I-5): привязка SQL/TTL-копий харнессов к исходнику server.py.

Харнессы — чистый stdlib, а `import server` на голом python невозможен:
server.py тянет fastapi, а gen_llm.py на 3.9 падает ещё до неё
(`dict | None` в аннотациях требует 3.10+). Проверено на этой машине.
Поэтому «живая» сверка через разбор ИСХОДНИКА server.py регулярками:
- WHERE guarded UPSERT'а захвата лока (_try_acquire_pair_lock),
- WHERE DELETE c owner-токеном в _release_pair_lock,
- WHERE guarded-обнуления баланса в _claim_echoes (T29) + константа ECHO_ETHER,
- вывод LOCK_TTL (override LOCK_TTL_SEC; иначе FLOOR/MARGIN × MAX_ATTEMPTS ×
  LLM_TIMEOUT — env-driven значения gen_llm/server).

Если сервер откатят к неатомарному захвату или поменяют TTL-формулу —
verify() валится ГРОМКО, а не молча «доказывает атомарность» самому себе.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER_PY = os.path.abspath(os.path.join(HERE, "..", "server.py"))
GEN_LLM_PY = os.path.abspath(os.path.join(HERE, "..", "gen_llm.py"))


def _norm(s: str) -> str:
    return " ".join(s.split())


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def _section(src: str, fn: str) -> str:
    """Тело функции fn из исходника (от def до следующего def верхнего уровня)."""
    i = src.index("def %s(" % fn)
    j = src.find("\ndef ", i + 1)
    return src[i:j if j != -1 else len(src)]


def _where_tail(sql: str) -> str:
    """Хвост после первого WHERE,whitespace-нормализованный."""
    m = re.search(r"\bWHERE\b(.*)", sql, re.S)
    if not m:
        raise AssertionError("в SQL харнесса нет WHERE — это не guarded-переход")
    return _norm(m.group(1))


def acquire_where() -> str:
    """WHERE-хвост guarded UPSERT из server._try_acquire_pair_lock (нормализованный).

    Срез до закрывающих \"\"\" отсекает и хвост строки, и аргумент ? —
    сравниваем только предикат перехода.
    """
    sec = _section(_read(SERVER_PY), "_try_acquire_pair_lock")
    m = re.search(r"ON CONFLICT\(pair_key\) DO UPDATE SET.*?WHERE\s+(.*?)\"\"\"",
                  sec, re.S)
    if not m:
        raise AssertionError(
            "server.py: в _try_acquire_pair_lock больше нет guarded "
            "ON CONFLICT(pair_key) DO UPDATE ... WHERE — харнесс зеркалил бы "
            "неатомарный захват; обнови харнесс вместе с сервером")
    return _norm(m.group(1))


def release_where() -> str:
    """WHERE-хвост DELETE из server._release_pair_lock без конечного ' ?' параметра."""
    sec = _section(_read(SERVER_PY), "_release_pair_lock")
    m = re.search(r"DELETE FROM pending_pairs\s+WHERE\s+(.*?)\"", sec, re.S)
    if not m or "owner" not in m.group(1):
        raise AssertionError(
            "server.py: _release_pair_lock больше не DELETE FROM pending_pairs "
            "... WHERE с owner-токеном — копия харнесса осиротела")
    return _norm(m.group(1))


def lock_ttl() -> float:
    """LOCK_TTL ровно по формуле из server.py при ТЕКУЩЕМ окружении.

    Совпадение с харнессом проверяется в чистом env (без LOCK_TTL_* в окружении
    прогона харнесса формула детерминирована дефолтами gen_llm/server).
    """
    src = _read(SERVER_PY)
    override = 'os.environ.get("LOCK_TTL_SEC")' in src
    floor = re.search(r"^LOCK_TTL_FLOOR\s*=\s*([\d.]+)", src, re.M)
    margin = re.search(r"^LOCK_TTL_MARGIN\s*=\s*([\d.]+)", src, re.M)
    formula = re.search(r"max\(LOCK_TTL_FLOOR, attempts \* timeout \* LOCK_TTL_MARGIN\)", src)
    timeout_default = re.search(r'os\.environ\.get\("LLM_TIMEOUT", "([\d.]+)"\)', src)
    if not (override and floor and margin and formula and timeout_default):
        raise AssertionError(
            "server.py: вывод LOCK_TTL (override LOCK_TTL_SEC, FLOOR, MARGIN, "
            "attempts*timeout) не найден — сервер откатили/переписали, "
            "харнесс рассинхронизирован")
    env_val = os.environ.get("LOCK_TTL_SEC")
    if env_val:
        return float(env_val)
    gl = _read(GEN_LLM_PY)
    m = re.search(r'MAX_ATTEMPTS = int\(os\.environ\.get\("LLM_MAX_ATTEMPTS", "(\d+)"\)\)', gl)
    if not m:
        raise AssertionError(
            "gen_llm.py: MAX_ATTEMPTS больше не int(env LLM_MAX_ATTEMPTS) — "
            "формула TTL в харнессе больше не повторяет сервер")
    attempts = int(os.environ.get("LLM_MAX_ATTEMPTS", m.group(1)))
    timeout = float(os.environ.get("LLM_TIMEOUT", timeout_default.group(1)))
    return max(float(floor.group(1)), attempts * timeout * float(margin.group(1)))


def score_upsert_where() -> str:
    """WHERE guarded-перехода _score_challenge (цель дня) из исходника server.py."""
    sec = _section(_read(SERVER_PY), "_score_challenge")
    m = re.search(
        r"ON CONFLICT\(day, device_id\) DO UPDATE SET.*?WHERE\s+(challenge_scores\.completed_at IS NULL)",
        sec, re.S)
    if not m:
        raise AssertionError(
            "server.py: в _score_challenge больше нет guarded UPSERT-перехода "
            "(ON CONFLICT(day, device_id) DO UPDATE ... WHERE completed_at IS NULL) "
            "— сценарий 4 харнесса зеркалил бы неатомарный скоринг")
    return _norm(m.group(1))


def score_topup_sql() -> str:
    """T09/U8 (d): TOPUP-копия — UPDATE проигравшего переход дедупа в
    _score_challenge (цель уже выполнена → очок без награды). Возвращает
    нормализованную полную строку SQL из исходника server.py."""
    sec = _section(_read(SERVER_PY), "_score_challenge")
    m = re.search(
        r'"(UPDATE challenge_scores SET points = points \+ 1[^"]*)"', sec)
    if not m:
        raise AssertionError(
            "server.py: в _score_challenge больше нет TOPUP-UPDATE "
            "(`UPDATE challenge_scores SET points = points + 1 ...`) — "
            "копия харнесса осиротела; обнови харнесс вместе с сервером")
    return _norm(m.group(1))


def claim_where() -> str:
    """T29 (I-1): WHERE guarded-обнуления баланса из server._claim_echoes.

    Харнесс зеркалит именно этот переход (compare-and-swap клейма отголосков):
    без привязки сценарий 5 доказывал бы атомарность своей копии, а не сервера.
    """
    sec = _section(_read(SERVER_PY), "_claim_echoes")
    m = re.search(r'"(UPDATE echoes SET balance = 0[^"]*)"', sec)
    if not m:
        raise AssertionError(
            "server.py: в _claim_echoes больше нет `UPDATE echoes SET balance = 0 "
            "... WHERE ...` — копия клейма в харнессе осиротела; обнови харнесс "
            "вместе с сервером")
    tail = _where_tail(m.group(1))
    if "balance = ?" not in tail:
        raise AssertionError(
            "server.py: обнуление в _claim_echoes больше не guarded (в WHERE нет "
            "`AND balance = ?`) — клейм снова уязвим к двойной выдаче эфира, "
            "сценарий 5 харнесса зеркалил бы неатомарный переход")
    return tail


def echo_ether() -> int:
    """ECHO_ETHER из server.py (эфир за один забранный отголосок)."""
    m = re.search(r"^ECHO_ETHER\s*=\s*(\d+)", _read(SERVER_PY), re.M)
    if not m:
        raise AssertionError(
            "server.py: константа ECHO_ETHER больше не `ECHO_ETHER = <число>` — "
            "копия клейма в харнессе больше не повторяет сервер")
    return int(m.group(1))


def verify(acquire_sql: str, release_sql: str, ttl: float, score_sql: str = None,
           topup_sql: str = None, claim_sql: str = None) -> None:
    """Сверить копии харнесса с исходником server.py; расхождение — падение.

    acquire_sql/release_sql/score_sql — полные строки харнесса; сравнивается их
    WHERE-хвост (whitespace-нормализованный) с эталонным хвостом из server.py.
    topup_sql (T09/U8 (d)) — полная TOPUP-строка харнесса: сравнивается
    целиком (в ней нет guarded-условия, важен и SET-хвост, и WHERE по ключу).
    claim_sql (T29 I-1) — строка обнуления баланса клейма: сравнивается
    WHERE-хвост, `AND balance = ?` обязано быть и в харнессе, и в сервере.
    """
    exp_ttl = lock_ttl()
    if abs(ttl - exp_ttl) > 1e-9:
        raise AssertionError(
            "HARNESS DRIFT: LOCK_TTL харнесса %s != %s (формула server.py при текущем env)"
            % (ttl, exp_ttl))
    pairs = (
        ("ACQUIRE WHERE", _where_tail(acquire_sql), acquire_where()),
        ("RELEASE WHERE", _where_tail(release_sql), release_where()),
    )
    if score_sql is not None:
        pairs += (("SCORE WHERE", _where_tail(score_sql), score_upsert_where()),)
    if topup_sql is not None:
        pairs += (("TOPUP SQL", _norm(topup_sql), score_topup_sql()),)
    if claim_sql is not None:
        pairs += (("CLAIM WHERE", _where_tail(claim_sql), claim_where()),)
    for label, mine, server_copy in pairs:
        if mine != server_copy:
            raise AssertionError(
                "HARNESS DRIFT: %s харнесса\n  %r\nне совпадает с server.py\n  %r\n"
                " — сервер изменили, харнесс молча проверяет старое" % (label, mine, server_copy))
