"""Task 4: wall-clock потолок оффлайн-аккумуляции (Part C, advisory).

Сервер НЕ перетирает Part C (opaque, server-wins нет) — он возвращает клиенту
advisory-кап `elapsed × min(rate, MAX_ACCRUAL_RATE_PER_SEC)`. Честный игрок,
заходивший дважды за 12ч подряд (24h wall-clock), получает полный 24h·rate —
потолок не «съедает» законные окна. Часы вперёд → elapsed clamp'ится сервером
в 0 (нельзя накопить в будущее).

Мутации-красные:
- `min(rate, MAX)` → `rate` без clamp: test_declared_rate_above_hard_max покраснеет.
- ceiling = elapsed без множимого rate: test_clamped покраснеет.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..")))

import server as srv  # noqa: E402


def test_two_12h_collections_over_24h_are_not_capped_away():
    # elapsed 24h при rate=1 → ceiling 24h·rate, покрывает оба 12ч окна
    assert srv._accrual_ceiling(24 * 3600.0, 1.0) >= 24 * 3600.0


def test_declared_rate_above_hard_max_is_clamped():
    assert srv._accrual_ceiling(100.0, srv.MAX_ACCRUAL_RATE_PER_SEC * 10) == 100.0 * srv.MAX_ACCRUAL_RATE_PER_SEC


def test_nonpositive_elapsed_yields_zero_ceiling():
    # часы сдвинуты вперёд → elapsed clamp'ится в 0 → потолок 0
    assert srv._accrual_ceiling(0.0, 1.0) == 0.0
    assert srv._accrual_ceiling(-5.0, 1.0) == 0.0
