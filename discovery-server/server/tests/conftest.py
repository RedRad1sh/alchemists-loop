"""
Общие fixtures для тестов сервера.
"""
import os
import subprocess
import sys
import time

import pytest
import sqlite3


_here = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("TEST_DB_PATH", os.path.join(_here, "test_discoveries.db"))
REL_DB_PATH = os.path.abspath(DB_PATH)
BASE_URL = os.environ.get("TEST_SERVER_URL", "http://localhost:8080/api")


def canonical_pair_key(a: str, b: str) -> str:
    return f"{min(a, b)}|{max(a, b)}"


def _wait_server(timeout: int = 15):
    """Ожидание готовности сервера."""
    import requests
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f"{BASE_URL}/health", timeout=2)
            if r.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.5)
    return False


@pytest.fixture(scope="session")
def process_server():
    """Запуск сервера как отдельного процесса для всех тестов."""
    # Очистка БД перед тестами
    db_path = REL_DB_PATH
    
    # Убиваем возможные остатки предыдущих запусков
    import signal
    try:
        subprocess.run(["pkill", "-f", "uvicorn.*server:app"], 
                       stderr=subprocess.DEVNULL, timeout=2)
    except Exception:
        pass
    time.sleep(0.5)
    
    if os.path.exists(db_path):
        os.remove(db_path)
    
    # Создание БД
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    
    schema_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schema.sql")
    conn.executescript(open(schema_path).read())
    
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    
    # Стартовый граф веществ и рецептов (та же функция, что и в проде)
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import seed
    seed.seed_db(conn)
    
    conn.commit()
    conn.close()
    
    # Запуск сервера
    env = os.environ.copy()
    env["DB_PATH"] = db_path
    env["TEST_SERVER_URL"] = BASE_URL
    # LLM-генерация в тестах — детерминированная заглушка (без сети).
    # Заглушка mock сама эмулирует «решение модели»: пара person|gold для неё
    # несочетаема (туман), wall|wall → «Дом», прочее — детерминированное имя.
    env["LLM_PROVIDER"] = "mock"
    
    server_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"],
        cwd=server_dir,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    
    try:
        if not _wait_server(15):
            proc.kill()
            pytest.fail("Сервер не поднялся за 15 секунд")
        
        yield
    finally:
        proc.terminate()
        proc.wait(timeout=5)


@pytest.fixture(scope="module")
def server(process_server):
    """Фикстура для совместимости — просто возвращает process_server."""
    return process_server
