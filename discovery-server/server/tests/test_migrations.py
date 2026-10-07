"""
Раннер версий схемы (задача 0 серверного плана S1).

Схема проекта была forward-only: schema.sql executescript + PRAGMA/ALTER. Это
переносит добавление, но не перестройку. Раннер добавляет плотную нумерацию
migrations/NNN_*.sql и таблицу schema_version; применённый файл больше никогда
не выполняется. Откатов нет — роль down-миграции играет снапшот БД перед
деплоем (README-server.md).
"""

import os
import sys
import sqlite3

import pytest


def _srv(tmp_path, monkeypatch):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "mig.db"))
    return srv


def _migrations_dir(srv, monkeypatch, tmp_path):
    """Свой каталог миграций: не писать в боевой migrations/ рядом с сервером."""
    d = tmp_path / "migrations"
    d.mkdir()
    monkeypatch.setattr(srv, "MIGRATIONS_DIR", str(d))
    return d


def _versions(srv):
    conn = srv.get_db()
    try:
        rows = conn.execute(
            "SELECT version, name FROM schema_version ORDER BY version").fetchall()
    finally:
        conn.close()
    return [(r["version"], r["name"]) for r in rows]


class TestRunner:
    def test_applies_pending_migration_once(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        d = _migrations_dir(srv, monkeypatch, tmp_path)
        (d / "001_probe.sql").write_text(
            "CREATE TABLE IF NOT EXISTS probe_t (id INTEGER PRIMARY KEY);",
            encoding="utf-8")
        srv.init_db()
        first = _versions(srv)
        assert first == [(1, "001_probe.sql")], first
        conn = srv.get_db()
        try:
            applied_at = conn.execute(
                "SELECT applied_at FROM schema_version WHERE version=1").fetchone()["applied_at"]
        finally:
            conn.close()
        # второй прогон ничего не применяет и не трогает applied_at:
        # идемпотентность по версии, а не по проверке каждой колонки
        srv.init_db()
        assert _versions(srv) == first
        conn = srv.get_db()
        try:
            again = conn.execute(
                "SELECT applied_at FROM schema_version WHERE version=1").fetchone()["applied_at"]
        finally:
            conn.close()
        assert again == applied_at, (again, applied_at)

    def test_applies_in_version_order(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        d = _migrations_dir(srv, monkeypatch, tmp_path)
        # записываем в обратном порядке создания — раннер сортирует по имени
        (d / "010_later.sql").write_text(
            "CREATE TABLE IF NOT EXISTS later_t (id INTEGER PRIMARY KEY);", encoding="utf-8")
        (d / "002_earlier.sql").write_text(
            "CREATE TABLE IF NOT EXISTS earlier_t (id INTEGER PRIMARY KEY);", encoding="utf-8")
        srv.init_db()
        assert _versions(srv) == [(2, "002_earlier.sql"), (10, "010_later.sql")]

    def test_broken_migration_rolls_back_whole_file(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        d = _migrations_dir(srv, monkeypatch, tmp_path)
        (d / "001_good.sql").write_text(
            "CREATE TABLE IF NOT EXISTS good_t (id INTEGER PRIMARY KEY);", encoding="utf-8")
        # вторая половина файла падает: первая половина не должна остаться
        (d / "002_broken.sql").write_text(
            "CREATE TABLE IF NOT EXISTS half_t (id INTEGER PRIMARY KEY);\n"
            "THIS IS NOT SQL;\n", encoding="utf-8")
        with pytest.raises(Exception):
            srv.init_db()
        assert _versions(srv) == [(1, "001_good.sql")], \
            "поломанная миграция не записывает версию и откатывает весь файл"
        conn = srv.get_db()
        try:
            half = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='half_t'").fetchone()
        finally:
            conn.close()
        assert half is None, "BEGIN IMMEDIATE/COMMIT внутри скрипта обязаны откатить half_t"

    def test_bad_filename_rejected(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        d = _migrations_dir(srv, monkeypatch, tmp_path)
        (d / "1_probe.sql").write_text("SELECT 1;", encoding="utf-8")
        with pytest.raises(RuntimeError) as exc:
            srv.init_db()
        assert "1_probe.sql" in str(exc.value)

    def test_missing_migrations_dir_is_fine(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "MIGRATIONS_DIR", str(tmp_path / "nope"))
        srv.init_db()
        assert _versions(srv) == []
