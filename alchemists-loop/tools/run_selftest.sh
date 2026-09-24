#!/usr/bin/env bash
# Назначение: локальный прогон автотеста (headless) с честным propagate кода
# выхода Godot. Сам раннер — tests/selftest.gd: он завершает процесс через
# g.get_tree().quit(0 if _fails == 0 else 1), поэтому код возврата этого скрипта
# есть код возврата самотеста и ничего больше: 0 — все проверки зелёные,
# 1 — есть упавшая проверка, 124 — прогон убит по таймауту, 127 — Godot не найден.
# Список не исчерпывающий: любой другой ненулевой код (краш Godot, 126 от timeout)
# проходит той же веткой FAIL со своим номером — отличить его от упавшей проверки
# можно только по самому числу.
#
# Godot берётся из $GODOT, иначе ищется в PATH. Лишние аргументы скрипта
# пробрасываются в аргументы игры, например: tools/run_selftest.sh --probe
#
# Прогон страхуется таймаутом: сюиты — headless-вычисления без интерактива,
# штатный прогон укладывается в секунды, 120 с — запас больше чем на порядок.
# Без него Godot, упавший в бесконечный цикл или зависший на await-хвосте,
# подвешивает прогон навсегда. Код таймаута (124) доходит наружу через
# status/exit так же честно, как код самотеста; если timeout (и gtimeout) в
# системе не нашли — прогон идёт без ограничения, но это печатается в stderr,
# а не молчит.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
    for candidate in godot godot4 godot-headless Godot Godot.exe; do
        if command -v "$candidate" >/dev/null 2>&1; then
            GODOT_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "$GODOT_BIN" ]; then
    echo "run_selftest: Godot не найден в PATH. Задайте GODOT=/путь/к/godot." >&2
    exit 127
fi

RUN_TIMEOUT_SEC=120
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
fi

if [ -z "$TIMEOUT_BIN" ]; then
    echo "run_selftest: timeout/gtimeout не найден — прогон БЕЗ ограничения времени; зависший Godot не завершится сам." >&2
    "$GODOT_BIN" --headless --path "$PROJECT_DIR" -- --selftest "$@"
else
    "$TIMEOUT_BIN" "$RUN_TIMEOUT_SEC" "$GODOT_BIN" --headless --path "$PROJECT_DIR" -- --selftest "$@"
fi
status=$?
if [ "$status" -eq 0 ]; then
    echo "run_selftest: SELFTEST PASS (exit 0)"
elif [ "$status" -eq 124 ]; then
    # Зависание — не упавшая проверка: сюита не дошла до конца, отчёта о кейсах нет.
    echo "run_selftest: SELFTEST TIMEOUT (exit 124, прогон убит через ${RUN_TIMEOUT_SEC} секунд)" >&2
else
    echo "run_selftest: SELFTEST FAIL (exit $status)" >&2
fi
exit "$status"
