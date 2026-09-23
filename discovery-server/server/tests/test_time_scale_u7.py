# -*- coding: utf-8 -*-
"""U7/T06 — pytest-регрессии единой временной шкалы.

ВНИМАНИЕ (отложенное исполнение): на машине разработки pytest НЕ установлен
и python 3.9 (server.py импортируется только под 3.10+fastapi — см.
tests/server_tie.py). Эти тесты НЕ прогонялись здесь; прогон — задача U8
вместе с остальным pytest-наследием. Логика проверок полностью повторяет
прогоняемый прямо сейчас stdlib-харнесс tests/harness_time_scale_u7.py
(тот же вырез хелперов из исходника, тот же аудит) — файл служит точкой
расширения для U8 (e2e через fixture server: /api/challenge + /api/events
под DAY_TZ_OFFSET).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_time_scale_u7 as h7  # noqa: E402


def test_time_scale_harness_parity():
    """Тот же харнесс, что и stdlib-прогон (pytest-вход для U8)."""
    h7.test_time_scale_harness()


def test_source_audit_no_mixed_scales():
    """Ни date('now'), ни локального datetime.now()/date.today()/timestamp()
    в код-пути server.py — только единые хелперы (падение = дрейф)."""
    h7._audit_source(h7._read(h7.SERVER_PY))


def test_day_tz_offset_parser():
    src = h7._read(h7.SERVER_PY)
    ns, _ = h7._extract_helpers(src)
    p = ns["_parse_day_tz_offset"]
    assert p("") == 0 and p("0") == 0
    assert p("+03:00") == 10800 and p("-03:00") == -10800
    assert p("+0530") == 19800 and p("-4") == -14400
    for bad in ("+3:60", "3", "msk", "+15:00"):
        try:
            p(bad)
            assert False, "мусорный DAY_TZ_OFFSET принят: %r" % bad
        except ValueError:
            pass
