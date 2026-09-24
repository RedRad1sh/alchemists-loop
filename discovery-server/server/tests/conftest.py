"""
Общие fixtures для тестов сервера (T09/U8 — герметичная тестовая инфраструктура).

Два слоя тестов:

1. Юнит-слой (большинство test_*.py) — in-process `fastapi.testclient.TestClient`
   без сетевого сервера. Фикстура `fresh_unit_db` (autouse, module scope) даёт
   КАЖДОМУ тестовому модулю свежий файл БД в tmp_path: никакого shared
   session-скрипта, никакого порядка зависимостей, никаких записей в рабочую БД.

2. Интеграционный слой (старые live-HTTP тесты) — реальный uvicorn-подпроцесс
   на ЭФЕМЕРНОМ порту (bind :0), своя свежая БД в tmp_path на каждый модуль.
   Никакого pkill/killall (на Windows их нет): остановка — terminate + wait
   с таймаутом + kill (Windows-safe).

Изоляция от прод-конфигурации:
- Окружение подменяется на уровне ИМПОРТА этого файла, до импорта `server`
  где-либо в тестах: gen_llm._load_dotenv НЕ перезаписывает переменные,
  уже присутствующие в os.environ, поэтому реальный .env (ключи OpenRouter,
  провайдер, смещение дня, таймауты/LOCK_TTL, дневные лимиты и кулдауны,
  отладочные флаги) в тестах не читается и сеть из тестов не ходит
  (LLM_PROVIDER=mock — детерминированная заглушка без HTTP). Запинено всё
  семейство env-ключей, которое реально читает server.py/gen_llm.py.
- BASE_URL строится ТОЛЬКО из ephemeral-порта фикстуры; прод-порт 8080
  явно запрещён ассертом. Тесты НЕ читают SERVER_URL/TEST_SERVER_URL.

Требование к интерпретатору: server.py/gen_llm.py используют синтаксис
Python 3.10+ (`dict | None`), поэтому на 3.9 импорт сервера падает с TypeError.
На неподходящем интерпретаторе здесь печатается ГРОМКОЕ предупреждение, а
коллекция падает на импорте server — это честный видимый отказ, а не тихий skip
(см. README-server.md и pin в requirements.txt).
"""
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

import pytest

_here = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.abspath(os.path.join(_here, ".."))

# Прод-порт сервера (__main__ uvicorn.run). Тестам трогать его запрещено:
# на нём может работать реальный сервер с реальной БД.
PROD_PORT = 8080

# Внешние модули, без которых server.py не импортируется (см. requirements.txt
# и импорты самого server.py/gen_llm.py). Только их отсутствие имеет право на
# тихий отказ фикстуры fresh_unit_db — см. там же.
_SERVER_RUNTIME_DEPS = {"fastapi", "pydantic", "starlette", "requests", "httpx", "uvicorn"}

# ---------------------------------------------------------------------------
# 1) Изоляция окружения: ДО любого импорта server/gen_llm в процессе pytest.
#    _load_dotenv не перезаписывает переменные, уже присутствующие в
#    os.environ, поэтому эти значения имеют приоритет над реальным .env.
#    Запинены ВСЕ переменные, которые реально читает server.py/gen_llm.py
#    (кроме системных APPDATA/XDG_DATA_HOME и адресного SERVER_URL, который
#    сервер использует только в __main__-print): тайминги, лимиты, кулдауны,
#    модели и отладочные флаги тоже берутся из тестовых дефолтов, а не из
#    продного .env (иначе LLM_TIMEOUT/LLM_MAX_ATTEMPTS незаметно меняли бы
#    LOCK_TTL, а ALCHEMY_*_DAILY_LIMIT/кулдауны — поведение квот).
#    Значения совпадают с дефолтами кода (README-server.md, таблица env).
# ---------------------------------------------------------------------------
_TEST_ENV = {
    # Детерминированная LLM-заглушка вместо сети/ключей (wall|wall → Дом,
    # fire|water → Пар, person|gold → «несочетаема»).
    "LLM_PROVIDER": "mock",
    "OPENROUTER_API_KEY": "",
    "LLM_API_KEY": "",
    "LLM_BASE_URL": "",
    "LLM_MODELS": "",  # mock-провайдер их не использует; продный список не течёт
    # Нулевое смещение дня: тесты не наследуют продный DAY_TZ_OFFSET.
    "DAY_TZ_OFFSET": "",
    # Тайминги генерации/лока: дефолты кода, LOCK_TTL выводится из них.
    "LLM_TIMEOUT": "30",
    "LLM_MAX_ATTEMPTS": "3",
    "LOCK_TTL_SEC": "",  # пусто → сервер выведет из MAX_ATTEMPTS×LLM_TIMEOUT
    "DB_BUSY_TIMEOUT_SEC": "10",
    # Дневные квоты/кулдауны (эксперименты, письма, атлас) — дефолты кода.
    "ALCHEMY_EXPERIMENT_COOLDOWN_SEC": "5",
    "ALCHEMY_EXPERIMENT_DAILY_LIMIT": "200",
    "ALCHEMY_EXPERIMENT_GLOBAL_DAILY_LIMIT": "10000",
    "ALCHEMY_LETTER_COOLDOWN_SEC": "30",
    "ALCHEMY_LETTER_DAILY_LIMIT": "3",
    "ALCHEMY_LETTER_GLOBAL_DAILY_LIMIT": "3000",
    "ALCHEMY_ATLAS_COOLDOWN_SEC": "60",
    "ALCHEMY_ATLAS_DAILY_LIMIT": "10",
    # Валидация чеков (T22): в тестах гейт всегда выключен — продные ключи
    # проверок платежей в тесты течь не должны (тесты с включённым гейтом
    # подменяют константы srv.RECEIPT_* сами).
    "ALCHEMY_RECEIPT_VALIDATION_URL": "",
    "ALCHEMY_RECEIPT_SERVICE_KEY": "",
    # Отладочные/логируемые переключатели: в тестах — молча (дефолт кода).
    "ALCHEMY_DEBUG": "",
    "LLM_DEBUG": "",
    "ALCHEMY_LOG_RAW": "",
    "LLM_HTTP_REFERER": "",
}
for _k, _v in _TEST_ENV.items():
    os.environ[_k] = _v

# Страховка: если какой-то тест импортирует server и триггерит startup без
# собственного monkeypatch srv.DB_PATH — пишет в ephemeral-каталог, а не в
# %APPDATA%/AlchemistsLoop (дефолт _resolve_db_path на машине разработчика).
_BOOTSTRAP_DB_DIR = tempfile.mkdtemp(prefix="alchemy-test-bootstrap-")
os.environ.setdefault("ALCHEMY_DB_PATH", os.path.join(_BOOTSTRAP_DB_DIR, "bootstrap.db"))

if sys.version_info < (3, 10):
    import warnings

    warnings.warn(
        "Тесты discovery-server требуют Python >= 3.10 (server.py/gen_llm.py "
        "используют `dict | None`). На этом интерпретаторе (%s) импорт server "
        "упадёт — коллекция/запуск тестов невозможны; см. README-server.md "
        "(stdlib-харнессы tests/harness_*.py работают и на 3.9)."
        % sys.version,
        RuntimeWarning,
        stacklevel=2,
    )


# ---------------------------------------------------------------------------
# Чистые helper'ы WITHOUT fastapi/uvicorn — импортируются и работают даже
# там, где серверный код не импортируется (py3.9, отсутствие зависимостей).
# ---------------------------------------------------------------------------
def canonical_pair_key(a: str, b: str) -> str:
    return f"{min(a, b)}|{max(a, b)}"


def free_port() -> int:
    """Порт, отданный ОС (bind на 0). Прод-порт 8080 запрещён ассертом."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    assert port != PROD_PORT, "ОС выдала прод-порт 8080 — тестам он запрещён"
    return port


def make_db_path(dir_path: str, name: str = "test.db") -> str:
    """Путь БД под tmp_path + обязательный «не прод» ассерт."""
    path = os.path.abspath(os.path.join(str(dir_path), name))
    assert "discoveries.db" not in path  # не рабочий/продовый файл
    return path


def prepare_db(db_path: str) -> str:
    """Создать схему + стартовый граф (stdlib sqlite3 + seed.py, без fastapi).

    Сам сервер на startup тоже вызывает init_db(); пред-создание нужно, чтобы
    путь БД в tmp_path и его содержимое проверялись до подъёма процесса.
    """
    import sqlite3

    if os.path.exists(db_path):
        os.remove(db_path)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    schema_path = os.path.join(SERVER_DIR, "schema.sql")
    with open(schema_path, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    if SERVER_DIR not in sys.path:
        sys.path.insert(0, SERVER_DIR)
    import seed

    seed.seed_db(conn)
    seed.seed_bots(conn)
    conn.commit()
    conn.close()
    return db_path


def _server_test_env(db_path: str) -> dict:
    """Окружение uvicorn-подпроцесса: свежая БД + mock-LLM + без продных ключей."""
    env = os.environ.copy()
    env.update(_TEST_ENV)
    env["ALCHEMY_DB_PATH"] = db_path
    env["DB_PATH"] = db_path
    return env


def wait_for_health(base_url: str, proc: subprocess.Popen, timeout: float = 30.0) -> bool:
    """Опрос /api/health через urllib (stdlib). При досрочной смерти процесса
    возвращаем False — вызывающий дампнет лог-файл."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with urllib.request.urlopen(f"{base_url}/health", timeout=2) as r:
                if r.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(0.25)
    return False


def _dump_log_tail(log_path: str, limit: int = 4000) -> str:
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        return text[-limit:]
    except OSError as e:
        return f"<лог не читается: {e}>"


# ---------------------------------------------------------------------------
# 2) Интеграционный слой: uvicorn-подпроцесс, ephemeral-порт, БД в tmp_path,
#    на каждый тестовый модуль — свежий сервер и свежая БД.
#    Уборка: terminate → wait(timeout) → kill (кроссплатформенно, без pkill).
#    Логи — в файл (PIPE без чтения дедлокает подпроцесс на Windows).
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module")
def process_server(tmp_path_factory):
    """Запуск реального uvicorn на ephemeral-порту. Возвращает base_url
    вида http://127.0.0.1:<port>/api — единственный источник адреса для
    интеграционных тестов (ruling: BASE_URL строится только из фикстуры)."""
    port = free_port()
    assert port != PROD_PORT, "интеграционный тест не должен занимать прод-порт 8080"
    db = make_db_path(tmp_path_factory.mktemp("procserver"), "process.db")
    prepare_db(db)
    log_path = os.path.join(tempfile.mkdtemp(prefix="alchemy-test-log-"), "server.log")
    env = _server_test_env(db)

    with open(log_path, "wb") as log:
        proc = subprocess.Popen(
            [
                sys.executable, "-m", "uvicorn", "server:app",
                "--host", "127.0.0.1", "--port", str(port),
                "--log-level", "warning",
            ],
            cwd=SERVER_DIR,
            env=env,
            stdout=log,
            stderr=log,
        )
        base_url = f"http://127.0.0.1:{port}/api"
        try:
            if not wait_for_health(base_url, proc, timeout=30):
                tail = _dump_log_tail(log_path)
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
                pytest.fail(f"Сервер не поднялся за 30 секунд (порт {port}).\n--- лог ---\n{tail}")
            yield base_url
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


@pytest.fixture(scope="module")
def base_url(process_server):
    """Адрес API запущенного тестового сервера — только из фикстуры."""
    assert f":{PROD_PORT}/" not in process_server, "BASE_URL указывает на прод-порт"
    return process_server


@pytest.fixture(scope="module")
def server(process_server):
    """Совместимость: старые тесты запрашивают `server` как маркер запуска
    подпроцесса; адрес берите из `base_url`."""
    return process_server


# ---------------------------------------------------------------------------
# 3) Юнит-слой: autouse-фикстура даёт каждому модулю свежий srv.DB_PATH в
#    tmp_path (in-process TestClient без uvicorn). Подмена пропускается только
#    когда серверный модуль недоступен по известной причине (нет внешних deps
#    либо py<3.10); прочие отказы импорта — см. комментарий в фикстуре.
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module", autouse=True)
def fresh_unit_db(tmp_path_factory):
    # Тишина допустима ровно в двух предсказуемых состояниях окружения: нет
    # серверных зависимостей (py<3.10 косвенно тоже). Всё прочее — «сломанный
    # server»: ImportError по внутреннему модулю (server/seed/gen_llm — их тут
    # нет в списке) или TypeError на 3.10+ обязан упасть, а не оставить юнит-
    # тесты без подмены DB_PATH (то есть пишет в bootstrap-файл).
    try:
        if SERVER_DIR not in sys.path:
            sys.path.insert(0, SERVER_DIR)
        import server as srv
    except ImportError as e:
        if (e.name or "").split(".")[0] not in _SERVER_RUNTIME_DEPS:
            raise
        yield None
        return
    except TypeError:
        if sys.version_info >= (3, 10):
            raise
        # py3.9: аннотации `dict | None` вычисляются на импорте (py_compile
        # при этом молчит). На 3.10+ такой TypeError — уже регресс кода.
        yield None
        return
    db = make_db_path(tmp_path_factory.mktemp("unitdb"), "unit.db")
    old = srv.DB_PATH
    srv.DB_PATH = db
    try:
        yield db
    finally:
        srv.DB_PATH = old
