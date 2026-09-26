#!/usr/bin/env python3
"""
Сброс первооткрытий: удаляет ВСЕ сгенерированные вещества, рецепты, отказы
и блокировки и возвращает БД к чистому стартовому графу (57 веществ /
53 рецепта).

Нужно, чтобы вычистить результаты старой логики генерации (имена из
удалённых «пулов» вроде «Бетон», «Кузница» и т.п.), которые были сохранены
в БД раньше.

Для точечной чистки (удалить конкретный рецепт, снять отказ) используйте
clean_db.py — он умеет list/rm/unreject/reset.

Использование:
    python3 reset_generated.py [путь_к_БД]

По умолчанию берётся srv.DB_PATH (ALCHEMY_DB_PATH/DB_PATH из окружения или
пользовательская папка данных — см. server.py)._
"""

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "server"))

import server as srv  # noqa: E402


def main() -> None:
    db = (
        sys.argv[1]
        if len(sys.argv) > 1
        else srv.DB_PATH
    )
    if not os.path.exists(db):
        print(f"БД не найдена: {db}")
        sys.exit(1)

    srv.DB_PATH = db
    srv.init_db()  # гарантируем схему и стартовый граф
    conn = srv.get_db()
    try:
        srv.reset_world(conn)
        conn.commit()
        n = conn.execute("SELECT COUNT(*) AS c FROM elements").fetchone()["c"]
        r = conn.execute("SELECT COUNT(*) AS c FROM recipes").fetchone()["c"]
        print(f"Готово. В БД снова {n} веществ / {r} рецептов (чистый стартовый граф).")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
