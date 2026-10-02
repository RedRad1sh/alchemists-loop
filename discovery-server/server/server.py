#!/usr/bin/env python3
"""
Сервер "первооткрытий" для игры "Петля алхимика".
Стек: Python 3 + FastAPI + uvicorn + SQLite.
Порт по умолчанию: 8080.

Запуск:
    uvicorn server:app --host 0.0.0.0 --port 8080 --reload
"""

import hashlib
import json
import logging
import random
import shutil
import math
import os
import re
import sys
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional

import sqlite3

# seed.py лежит рядом с server.py и содержит стартовый граф веществ.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import seed
import gen_llm
from gen_llm import GLYPH_PARAM, GLYPHS, LLMGenerator, LLMError, TAGS, is_glyph

# Логирование: «alchemy.llm» (gen_llm.py) и «alchemy» (этот модуль).
# Уровень INFO по умолчанию; DEBUG при ALCHEMY_DEBUG=1 или LLM_DEBUG=1.
log = logging.getLogger("alchemy")


def _setup_logging() -> None:
    if logging.getLogger().handlers:
        return
    level = logging.DEBUG if (os.environ.get("ALCHEMY_DEBUG") == "1" or os.environ.get("LLM_DEBUG") == "1") else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


_setup_logging()

from fastapi import FastAPI, HTTPException, Query, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from pydantic import ValidationError

import dashboard
import admin

# ---------------------------------------------------------------------------
# Конфигурация
# ---------------------------------------------------------------------------
def _user_data_db_path() -> str:
    """БД в пользовательской папке данных (appdata), а не рядом с кодом."""
    app = "AlchemistsLoop"
    if os.name == "nt":  # Windows: %APPDATA%
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
    elif sys.platform == "darwin":  # macOS: ~/Library/Application Support
        base = os.path.expanduser("~/Library/Application Support")
    else:  # Linux: $XDG_DATA_HOME или ~/.local/share
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, app, "discoveries.db")


def _resolve_db_path() -> str:
    # Явный путь из окружения (ALCHEMY_DB_PATH или старый DB_PATH) имеет приоритет.
    env = os.environ.get("ALCHEMY_DB_PATH") or os.environ.get("DB_PATH")
    if env:
        return os.path.abspath(env)
    target = _user_data_db_path()
    legacy = os.path.join(os.path.dirname(os.path.abspath(__file__)), "discoveries.db")
    # Миграция: если в новом месте БД ещё нет, а рядом со скриптом лежит старая —
    # переносим её, чтобы не потерять уже открытые вещества.
    if not os.path.exists(target) and os.path.exists(legacy):
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(legacy, target)
            print(f"База перенесена: {legacy} -> {target}")
        except OSError as e:
            print(f"Не удалось перенести базу {legacy} -> {target}: {e}")
    return target


DB_PATH = _resolve_db_path()
SERVER_URL = os.environ.get("SERVER_URL", "http://localhost:8080")
# U5-fix (review) / I-3: TTL обязан переживать ХУДШЕЕ окно генерации, иначе
# живой держатель лока теряет его посреди LLM-вызова и второй запрос лезет
# генерировать ту же пару (двойная трата бюджета). Окно env-управляемое
# (README советует поднимать LLM_TIMEOUT), поэтому НЕ хардкод: выводим из
# фактических MAX_ATTEMPTS (gen_llm, учитывает LLM_MAX_ATTEMPTS и .env —
# gen_llm импортирован выше) × LLM_TIMEOUT с запасом на валидацию/запись;
# прямой override — LOCK_TTL_SEC; нижняя граница — LOCK_TTL_FLOOR.
LOCK_TTL_FLOOR = 120.0   # сек: минимум, даже если конфигурация генерации мельче
LOCK_TTL_MARGIN = 1.25    # запас поверх худшего окна генерации


def _lock_ttl_seconds() -> float:
    override = os.environ.get("LOCK_TTL_SEC")
    if override:
        return float(override)
    attempts = int(getattr(gen_llm, "MAX_ATTEMPTS", 3))
    timeout = float(os.environ.get("LLM_TIMEOUT", "30"))
    return max(LOCK_TTL_FLOOR, attempts * timeout * LOCK_TTL_MARGIN)


LOCK_TTL = _lock_ttl_seconds()  # секунд: сколько пара считается «в обработке» (защита от гонок)
# T04: после перевода генерирующих эндпоинтов в threadpool писатели — потоки;
# ожидаем блокировку WAL-писателя не дольше этого, дальше — ошибка.
# T09/U8 (e): нечисловое значение окружения должно падать с внятной ошибкой,
# а не с голым ValueError('could not convert...') без имени переменной.
_raw_db_busy_timeout = os.environ.get("DB_BUSY_TIMEOUT_SEC", "10")
try:
    DB_BUSY_TIMEOUT_SEC = float(_raw_db_busy_timeout)
except ValueError:
    raise ValueError(
        "DB_BUSY_TIMEOUT_SEC должен быть числом секунд, получено %r"
        % _raw_db_busy_timeout
    )
# Эксперименты — это явные LLM-backed запросы из Experiment Bench. Значения
# намеренно конфигурируются окружением: расходы на LLM не должны быть спрятаны
# в клиентской экономике. Кэшированные/curated ответы лимит не расходуют.
# Квота резервируется на сервере по ФАКТУ обращения к генератору (см.
# _generate_for_pair), а не по клиентскому флагу experiment.
EXPERIMENT_COOLDOWN_SEC = float(os.environ.get("ALCHEMY_EXPERIMENT_COOLDOWN_SEC", "5"))
EXPERIMENT_DAILY_LIMIT = int(os.environ.get("ALCHEMY_EXPERIMENT_DAILY_LIMIT", "200"))
EXPERIMENT_GLOBAL_DAILY_LIMIT = int(os.environ.get("ALCHEMY_EXPERIMENT_GLOBAL_DAILY_LIMIT", "10000"))
# Письма Светика — отдельный дневной бюджет LLM-вызовов (не смешивать с
# экспериментами): генерация намёка тоже стоит денег.
LETTER_COOLDOWN_SEC = float(os.environ.get("ALCHEMY_LETTER_COOLDOWN_SEC", "30"))
LETTER_DAILY_LIMIT = int(os.environ.get("ALCHEMY_LETTER_DAILY_LIMIT", "3"))
LETTER_GLOBAL_DAILY_LIMIT = int(os.environ.get("ALCHEMY_LETTER_GLOBAL_DAILY_LIMIT", "3000"))
# Атлас — общемировая страница (1 генерация на сутки), device-ключа нет:
# квота резервируется по факту LLM-вызова под фиксированным мировым ключом ""
# (см. _ensure_atlas). Отдельный бюджет, чтобы отказные ретраи атласа не
# сжигали письма/эксперименты; дневной лимит считается вместе (per-key и
# мировой счётчики здесь совпадают по смыслу).
ATLAS_COOLDOWN_SEC = float(os.environ.get("ALCHEMY_ATLAS_COOLDOWN_SEC", "60"))
ATLAS_DAILY_LIMIT = int(os.environ.get("ALCHEMY_ATLAS_DAILY_LIMIT", "10"))

# ---------------------------------------------------------------------------
# T22: ВАЛИДАЦИЯ ПЛАТЁЖНЫХ ЧЕКОВ (состояние на сегодня — честно: гейт выключен)
#
# Реального вызова Google Play Developer API / RuStore API здесь НЕТ: в этом
# проекте нет ни сервисных ключей, ни сети. Поэтому конфигурация по умолчанию
# обязана «отказывать в проверке», а не «пропускать чек»: при пустом
# ALCHEMY_RECEIPT_VALIDATION_URL или пустом ALCHEMY_RECEIPT_SERVICE_KEY
# _validate_receipt_with_vendor() возвращает только verified=False (см. её
# докстринг), а /api/receipt/verify отвечает 503 vendor_validation_disabled.
# Сервер с включённым гейтом, но без реального вызова магазина, тоже честно
# отказывает.
# Единственный путь к verified=True — ответ ворендора (см. TODO(release)).
# ---------------------------------------------------------------------------
RECEIPT_VALIDATION_URL = os.environ.get("ALCHEMY_RECEIPT_VALIDATION_URL", "")
RECEIPT_SERVICE_KEY = os.environ.get("ALCHEMY_RECEIPT_SERVICE_KEY", "")
# Причины, означающие «валидатор не смог ответить» (не «чек плохой»): клиент
# трактует их как unavailable — в отладочной сборке локальное начисление
# допускается, в релизной — нет.
RECEIPT_UNAVAILABLE_REASONS = ("vendor_validation_disabled", "vendor_validation_not_implemented")
# Белый список провайдеров = клиентские store_id (alchemists-loop/autoload/app.gd).
RECEIPT_PROVIDERS = ("google_play", "rustore")
# ВНИМАНИЕ (расхождение каталогов): это ДУБЛЬ alchemists-loop/data/monetization.json
# (products[].store_sku), продублирован сознательно — сервер не читает клиентский
# каталог. Добавишь SKU в игру и не обновишь этот кортеж → валидатор честно
# откажет с unknown_sku (в релизе = товар не будет выдан). Синхронизация списков
# — ручной шаг релиза.
RECEIPT_SKUS = (
    "al_loop_ether_500",
    "al_loop_ether_1500",
    "al_loop_sage_gold_1",
    "al_loop_starter_2026",
    "al_loop_remove_ads",
)

# ---------------------------------------------------------------------------
# T06: ЕДИНАЯ ВРЕМЕННАЯ ШКАЛА СЕРВЕРА.
# Граница «суток» обязана быть ОДНОЙ для всех фич: цель дня (_ensure_challenge/
# _score_challenge), письма (_date_minus/бэклог), атлас, жила/ярмарка
# (_week_key/_fair_ensure/last_seen), лента today_events, дневные квоты
# (_reserve_llm_generation). Единственный источник времени — _now_dt():
# текущий момент UTC, сдвинутый на фиксированный DAY_TZ_OFFSET (например
# "+03:00" — сутки «пришпилены» к МСК; пусто/0 = UTC). Все дневные ключи
# (_today/_today_date) и все created_at/first_at, которые пишет сервер
# (_now_iso), идут только через эти хелперы. Вызовы SQLite date('now')/
# datetime('now') в Python-SQL больше НЕ используются — дата считается в
# Python и передаётся параметром, иначе смещение применилось бы не ко всем
# сравнениям. Дефолты схемы DEFAULT (datetime('now')) остаются UTC: эти
# колонки (created_at у letters/atlas_pages/players-легаси, first_at у
# resonance_seen/vein_points) — pure audit: с дневными ключами не
# сравниваются (аудит — в комментариях schema.sql). Эпоха time.time()
# (lock_ts, last_at в квотах) от TZ не зависит и НЕ переводится:
# wall-clock/NTP-скачок на ней ограничен лишь запасом LOCK_TTL (U6 M2).
# Forward-only: старые строки в смешанных шкалах не бэкфиллятся; с момента
# деплоя все записи равномерны, а дневные ключи существующих «дней»
# перевернутся один раз (разовый сдвиг границы — принятый компромисс).
def _parse_day_tz_offset(raw: str) -> int:
    """DAY_TZ_OFFSET: '[+-]HH[:MM]' (напр. '+03:00', '-4', '+0530'); ''/0 — UTC.
    Нераспознанное значение — падение на старте (лучше не стартануть, чем
    молча жить в неправильной шкале и разъезжать границами дня)."""
    raw = (raw or "").strip()
    if raw in ("", "0", "utc", "UTC", "+0", "-0"):
        return 0
    m = re.fullmatch(r"([+-])(\d{1,2})(?::?(\d{2}))?", raw)
    if not m:
        raise ValueError("DAY_TZ_OFFSET должен быть вида '+03:00' / '-4' / '0', получено %r" % raw)
    sign = -1 if m.group(1) == "-" else 1
    hours, minutes = int(m.group(2)), int(m.group(3) or 0)
    if hours > 14 or minutes > 59:
        raise ValueError("DAY_TZ_OFFSET вне диапазона ±14:00: %r" % raw)
    return sign * (hours * 3600 + minutes * 60)


DAY_TZ_OFFSET_SEC = _parse_day_tz_offset(os.environ.get("DAY_TZ_OFFSET", ""))


def _now_dt() -> datetime:
    """Серверная «сейчас» (naive): UTC + DAY_TZ_OFFSET. ЕДИНСТВЕННАЯ точка,
    откуда всё остальное время сервера берёт шкалу (T06)."""
    return datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=DAY_TZ_OFFSET_SEC)


def _now_iso() -> str:
    """Метка времени для записей сервера в единой шкале (isoformat с 'T' —
    на нём завязана миграция U6, отличать Python-записи от sqlite-дефолтов)."""
    return _now_dt().isoformat()


def _today() -> str:
    """Ключ дня 'YYYY-MM-DD' в единой серверной шкале (UTC+DAY_TZ_OFFSET)."""
    return _now_dt().strftime("%Y-%m-%d")


def _today_date() -> date:
    """Сегодняшний datetime.date в единой шкале (недельный слой, fallback'ы)."""
    return _now_dt().date()


# Резонанс первооткрывателя (v24): чужой повтор твоего вещества → отголосок.
ECHO_ETHER = 5   # эфир за один забранный отголосок
ECHO_CAP = 20    # максимум незабранных отголосков (вечный счётчик без капа)
RES_MILESTONES = (10, 50, 100)  # вехи: +реген / +кап / золотая рамка
# При недоступности LLM решение НЕ фиксируется: пара остаётся кандидатом,
# её можно будет сгенерировать позже (никаких «пулов» произвольных имён).

# Ежедневная цель: целевой ингредиент дня. Цель личная — награду получает
# первое закрытие цели этим устройством за день; от дня фиксируется только
# первый справившийся (`first_nick`). Выбор детерминирован по дате.
CHALLENGE_TARGETS = [
    "gold", "crystal", "lightning", "volcano", "rainbow", "sun",
    "ice", "storm", "tornado", "metal", "life", "desert", "boat", "person",
]

app = FastAPI(
    title="Алхимические первооткрытия",
    description="Сервер для регистрации нового вещества, полученного варкой неизвестной пары",
    version="1.0.0",
)

# Статика (CSS/JS для дашборда/админки)
_static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
os.makedirs(_static_dir, exist_ok=True)
app.mount("/static", StaticFiles(directory=_static_dir), name="static")

# Дашборд и админ-панель (подключаются после init_db в startup)
_dashboard_setup = False

# ---------------------------------------------------------------------------
# Pydantic-модели
# ---------------------------------------------------------------------------

# Слаг вещества: вывод slugify() — строчные латиница/цифры/дефис. Валидируется
# на уровне модели (T07): в a/b чужеродный текст (HTML/эмодзи/мусор) не должен
# доходить до БД и генератора.
_SLUG_PATTERN = r"^[a-z0-9][a-z0-9\-]{0,63}$"

class BrewCheckRequest(BaseModel):
    a: str = Field(..., min_length=1, max_length=64, pattern=_SLUG_PATTERN,
                   description="ID первого ингредиента (слаг)")
    b: str = Field(..., min_length=1, max_length=64, pattern=_SLUG_PATTERN,
                   description="ID второго ингредиента (слаг)")
    nick: str = Field(..., min_length=1, max_length=64, description="Ник игрока")
    device_id: str = Field(..., min_length=1, max_length=128, description="Уникальный ID устройства")
    # Явная метка Experiment Bench. В первой версии arity=2; поле позволяет
    # отличить оплаченный LLM-запрос от обычного чтения известной пары.
    # Только UX/аналитика: квота LLM решается на сервере по факту генерации.
    experiment: bool = False

class BrewCheckResponse(BaseModel):
    ok: bool
    pair_key: str
    found: bool
    status: str = "candidate"  # known | candidate | not_combinable | processing
    out: Optional[dict] = None
    discoverer: Optional[dict] = None
    pending: bool = False
    message: str
    # T02: канонический «витринный» ник устройства (для новой системы с занятым
    # ником — унифицированный, напр. «Алхимик-a1b2»). Клиент сверяет его с /api/me.
    nick: str = ""

class DiscoverRequest(BrewCheckRequest):
    pass

class DiscoveryData(BaseModel):
    id: int
    slug: str
    name: str
    color: str
    layer: int
    category: str
    glyph: str = ""
    d: str = ""
    pair_key: str
    a: str
    b: str
    author: Optional[str] = None
    avatar: Optional[dict] = None
    seq: int
    created_at: Optional[str] = None
    gen_method: Optional[str] = None  # "llm" | "linked"
    reused: bool = False  # результат привязан к уже существующему веществу
    tag: str = ""  # тег природы (v30, недельный слой)

class DiscoverResponse(BaseModel):
    ok: bool
    discovery: Optional[DiscoveryData] = None
    already_known: bool = False
    status: str = "created"  # created | known | not_combinable | unavailable
    message: str
    challenge: Optional[dict] = None  # состояние ежедневной цели: {won, first, target_name}
    vein: Optional[dict] = None  # бонус жилы: {points, streak_added, streak_count, cap_reached} | None

class EventData(BaseModel):
    pair_key: str
    a: str
    b: str
    a_name: str = ""
    b_name: str = ""
    out: str
    out_name: str
    discoverer: Optional[str] = None
    avatar: Optional[dict] = None
    created_at: Optional[str] = None
    ago_sec: int = 0

class EventsResponse(BaseModel):
    ok: bool
    events: list[EventData]

class ChallengeResponse(BaseModel):
    ok: bool
    day: str
    target: str
    target_name: str
    hint: str
    first_nick: Optional[str] = None
    first_avatar: Optional[dict] = None
    completions: int = 0
    my_points: int = 0
    my_points_total: int = 0  # вечный суммарный счёт очков (вехи Дневного круга, v29)
    today_events: int = 0

class ElementData(BaseModel):
    id: int
    slug: str
    name: str
    color: str
    layer: int
    category: str
    glyph: str = ""
    d: str = ""
    author: Optional[str] = None
    avatar: Optional[dict] = None
    created_at: Optional[str] = None

class WorldResponse(BaseModel):
    ok: bool
    elements: list[ElementData]
    page: int
    per_page: int
    total: int

class HallEntry(BaseModel):
    rank: int
    nick: str
    avatar: Optional[dict] = None
    count: int
    updated_at: Optional[str] = None

class HallResponse(BaseModel):
    ok: bool
    hall: list[HallEntry]

class HealthResponse(BaseModel):
    ok: bool
    version: str

class ProfileRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128, description="Уникальный ID устройства")
    nick: str = Field("", max_length=64, description="Ник игрока (2..24 символа после очистки)")

class HouseGuest(BaseModel):
    nick: str
    avatar: dict
    day: str


class HouseVisitRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    host_nick: str = Field(..., min_length=1, max_length=64)


class HouseVisitResponse(BaseModel):
    ok: bool
    found: bool = True
    visits_week: int = 0


class ProfileResponse(BaseModel):
    ok: bool
    nick: str
    device_id: str
    avatar: dict
    # γ «Гостевая книга»: счётчик гостей за неделю и приватная лента «кто
    # именно» — только в СВОЁМ профиле (публичный домик имён не отдаёт).
    house_visits_week: int = 0
    house_visitors: list[HouseGuest] = []


class RejectedResponse(BaseModel):
    ok: bool
    rejected: list[str]


class HouseRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    nick: str = Field(..., min_length=1, max_length=64)
    house: dict = {}


class HouseResponse(BaseModel):
    ok: bool
    nick: str
    avatar: Optional[dict] = None
    house: Optional[dict] = None
    found: bool = True
    visits_week: int = 0      # γ: уникальных гостей за 7 дней (0, а не null)


class RatingRow(BaseModel):
    rank: int
    nick: str
    avatar: Optional[dict] = None
    discoveries: int = 0
    elements: int = 0
    points: int = 0
    house_built: bool = False
    house_guests: int = 0
    updated_at: Optional[str] = None


class RatingResponse(BaseModel):
    ok: bool
    rows: list[RatingRow]
    me: Optional[RatingRow] = None


class EchoDescendant(BaseModel):
    name: str
    slug: str
    by: Optional[str] = None
    at: Optional[str] = None


class EchoTop(BaseModel):
    name: str
    slug: str
    count: int = 0


class EchoesResponse(BaseModel):
    ok: bool
    nick: str = ""
    balance: int = 0
    total: int = 0
    cap: int = 20
    echo_ether: int = 5
    milestones: dict = {}
    top: list[EchoTop] = []
    descendants: list[EchoDescendant] = []
    descendants_total: int = 0
    apprentice: Optional[dict] = None


class EchoesClaimRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)


class EchoesClaimResponse(BaseModel):
    ok: bool
    claimed: int = 0
    ether: int = 0
    total: int = 0


class LetterData(BaseModel):
    # NOTE: слаги ответа (a/b) клиенту не отдаём никогда — иначе спойлер.
    day: str
    a_name: str = ""  # только если разгадано / приоткрыто (см. ниже)
    b_name: str = ""
    len_a: int = 0  # длины слов — рамка загадки, видны всегда
    len_b: int = 0
    known_a: list = []  # приоткрытые буквы [[idx, char], ...]
    known_b: list = []
    hint: str = ""
    solved: bool = False
    revealed: bool = False  # лежит ≥2 дней — Светик называет первое вещество


class LettersResponse(BaseModel):
    ok: bool
    today: Optional[LetterData] = None
    backlog: list[LetterData] = []
    solved_total: int = 0


class LetterSolveRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    a: str = Field(..., min_length=1, max_length=128)  # слаги сваренной пары
    b: str = Field(..., min_length=1, max_length=128)


class LetterSolveResponse(BaseModel):
    ok: bool
    matched: bool = False  # пара совпала с неразгаданным письмом
    day: str = ""  # день разгаданного письма ("" если не совпало)
    solved_total: int = 0
    milestone: bool = False  # каждое 5-е → +кап на клиенте


class AtlasTodayData(BaseModel):
    # NOTE: слаги ответа клиенту не отдаём никогда (как в письмах).
    day: str
    riddle: str = ""
    len_a: int = 0
    len_b: int = 0
    known_a: list = []
    known_b: list = []
    solvers: int = 0  # сколько устройств уже разгадали
    solved_by_me: bool = False
    # имена — только если я разгадал (для просмотра своей страницы)
    a_name: str = ""
    b_name: str = ""


class AtlasHistoryData(BaseModel):
    day: str
    riddle: str = ""
    a_name: str = ""
    b_name: str = ""
    solved_by_me: bool = False


class AtlasTodayResponse(BaseModel):
    ok: bool
    today: Optional[AtlasTodayData] = None  # None = LLM недоступна, день ждёт
    history: list[AtlasHistoryData] = []  # прошлые дни с ответами (до 7)
    solved_total: int = 0  # моих разгаданных страниц


class AtlasSolveRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    a: str = Field(..., min_length=1, max_length=128)
    b: str = Field(..., min_length=1, max_length=128)


class AtlasSolveResponse(BaseModel):
    ok: bool
    matched: bool = False
    solved_total: int = 0
    milestone: bool = False  # каждая 10-я → +кап на клиенте


class WeekStatusResponse(BaseModel):
    ok: bool
    week: str = ""
    vein: dict = {}  # {tag1, tag2, spread, my_hits, my_streaks, streak_cap}
    fair: dict = {}  # {tag, goal, progress, apprentice, closed, my_contrib, claimed, prev}


class FairBrewRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    a: str = Field(..., min_length=1, max_length=128)
    b: str = Field(..., min_length=1, max_length=128)


class FairBrewResponse(BaseModel):
    ok: bool
    counted: bool = False
    progress: int = 0
    goal: int = 0
    contrib: int = 0
    closed: bool = False


class FairClaimRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)


class FairClaimResponse(BaseModel):
    ok: bool
    grants: list = []  # [{week, kind: regen|ether, amount}]


# T22: проверка платёжного чека. Сырой receipt_token в БД НЕ сохраняется —
# сервер хранит только его SHA-256 (см. _receipt_hash и таблицу receipts).
class ReceiptVerifyRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    provider: str = Field(..., min_length=1, max_length=32)
    sku: str = Field(..., min_length=1, max_length=128)
    receipt_token: str = Field(..., min_length=1, max_length=4096)


class ReceiptVerifyResponse(BaseModel):
    ok: bool
    verified: bool = False
    status: str = ""        # '' | pending | processed
    reason: str = ""        # verified | vendor_validation_* | vendor_rejected |
                            # receipt_device_mismatch | receipt_sku_mismatch |
                            # receipt_provider_mismatch | unknown_* | empty_*
    receipt_hash: str = ""  # SHA-256 токена: клиент сверяет ответ со своим запросом


class VeinFindRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    pair_key: str = Field(..., min_length=1, max_length=256)
    tag: str = Field(..., min_length=1, max_length=64)
    cycle_id: str = Field(..., min_length=1, max_length=128)


class VeinFindResponse(BaseModel):
    ok: bool
    points: int = 0
    streak_added: bool = False
    streak_count: int = 0
    cap_reached: bool = False
    cycle_id: str = ""
    error: str = ""


class VeinPourRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    idempotency_key: str = Field(..., min_length=1, max_length=256)


class VeinPourResponse(BaseModel):
    ok: bool
    already_poured: bool = False


class CycleStatusResponse(BaseModel):
    ok: bool
    cycle_id: str = ""
    tag1: str = ""
    tag2: Optional[str] = None
    state: str = ""
    world_finds: int = 0
    my_points: int = 0
    my_streak: int = 0
    # план 2 R5 (аддитивно): начало цикла и порог — клиенту нужны для
    # telemetry vein_cycle_spread (reason/duration_days).
    started_at: str = ""
    spread_threshold: int = 0


# ---------------------------------------------------------------------------
# Работа с БД
# ---------------------------------------------------------------------------

def get_db() -> sqlite3.Connection:
    """Фабрика соединений. Каждый запрос получает своё соединение.

    T04 + T29 (I-1), ЕДИНОЕ обоснование формы хендлеров (его не повторяем в 25
    местах, см. README-server.md): любой HTTP-хендлер, который трогает SQLite, —
    sync `def`. FastAPI/Starlette отводит такие эндпоинты в threadpool, и
    писатель не держит единый event loop: до T29 21 async-хендлер синхронно
    писал в БД и мог заблокировать loop на весь DB_BUSY_TIMEOUT_SEC (дефолт 10с)
    на конкурирующем локе — вплоть до /api/health. Осознанные исключения:
    `startup` (зовётся через asyncio.run из тестов) и `health` (в БД не ходит).
    Форму держит тест-инвариант tests/test_u5_concurrency.py
    ::test_generating_handlers_are_sync_def (правило по app.routes, а не список
    имён), а гонку «прочитал-записал» внутри потоков — guarded-переходы вида
    _claim_echoes/_try_acquire_pair_lock/_score_challenge.

    Соединения создаются, используются и закрываются в одном рабочем потоке —
    check_same_thread остаётся True (дефолт): любое случайное перетекание
    соединения между потоками упадёт явно, а не испорченной базой. WAL включён;
    busy_timeout задан явно (timeout=), т.к. писатели теперь потоки и краткие
    блокировки сериализуются ожиданием.
    """
    os.makedirs(os.path.dirname(os.path.abspath(DB_PATH)), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=DB_BUSY_TIMEOUT_SEC)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(f"PRAGMA busy_timeout={int(DB_BUSY_TIMEOUT_SEC * 1000)}")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def canonical_pair_key(a: str, b: str) -> str:
    """Нормализованный ключ пары (сортировка по алфавиту)."""
    if a == b:
        return f"{a}|{a}"
    return f"{min(a, b)}|{max(a, b)}"

def init_db():
    """Инициализация БД: создать таблицы и загрузить стартовый граф веществ."""
    conn = get_db()
    try:
        # Heal ДО schema.sql: частичный UNIQUE-индекс в схеме упал бы на
        # БД, созданной Pre-F2-кодом с двумя открытыми циклами (гонка
        # _ensure_active_cycle). schema.sql выполняется executescript-ом,
        # где IntegrityError перехватить нельзя построчно.
        has_cycles = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='vein_cycles'"
        ).fetchone()
        if has_cycles:
            open_cycles = conn.execute(
                "SELECT cycle_id FROM vein_cycles "
                "WHERE state IN ('active', 'spread') ORDER BY started_at DESC"
            ).fetchall()
            if len(open_cycles) > 1:
                conn.execute(
                    "UPDATE vein_cycles SET state='closed', ended_at=? "
                    "WHERE state IN ('active', 'spread') AND cycle_id != ?",
                    (_now_iso(), open_cycles[0]["cycle_id"]),
                )
        # Выполняем schema.sql (только DDL)
        schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
        if os.path.exists(schema_path):
            with open(schema_path, "r", encoding="utf-8") as f:
                schema_sql = f.read()
            conn.executescript(schema_sql)

        # миграция старых БД: колонки glyph и d
        cols = {r["name"] for r in conn.execute("PRAGMA table_info(elements)").fetchall()}
        if "glyph" not in cols:
            conn.execute("ALTER TABLE elements ADD COLUMN glyph TEXT NOT NULL DEFAULT ''")
        if "d" not in cols:
            conn.execute("ALTER TABLE elements ADD COLUMN d TEXT NOT NULL DEFAULT ''")
        if "name_norm" not in cols:
            conn.execute("ALTER TABLE elements ADD COLUMN name_norm TEXT")
        if "resonance_count" not in cols:
            conn.execute("ALTER TABLE elements ADD COLUMN resonance_count INTEGER NOT NULL DEFAULT 0")
        if "tag" not in cols:
            conn.execute("ALTER TABLE elements ADD COLUMN tag TEXT NOT NULL DEFAULT ''")

        # миграция players: колонки домика (для открытия чужих домов)
        pcols = {r["name"] for r in conn.execute("PRAGMA table_info(players)").fetchall()}
        if "house" not in pcols:
            conn.execute("ALTER TABLE players ADD COLUMN house TEXT")
        if "house_updated_at" not in pcols:
            conn.execute("ALTER TABLE players ADD COLUMN house_updated_at TEXT")
        if "last_seen" not in pcols:
            conn.execute("ALTER TABLE players ADD COLUMN last_seen TEXT")

        # миграция challenges: winner_* → first_* (личная цель вместо гонки)
        ccols = {r["name"] for r in conn.execute("PRAGMA table_info(challenges)").fetchall()}
        if "first_nick" not in ccols:
            conn.execute("ALTER TABLE challenges ADD COLUMN first_nick TEXT")
        if "first_device" not in ccols:
            conn.execute("ALTER TABLE challenges ADD COLUMN first_device TEXT")

        # U6/T05: разнесение challenge/vein-каналов очков.
        # 1) challenge_scores.completed_at — явный флаг «цель дня выполнена».
        #    Раньше флагом был сам факт строки, а в таблицу лились и vein-очки:
        #    игрок с попаданием в жилу больше не мог получить won.
        # 2) vein_points — отдельная таблица vein-канала (создаётся выше из
        #    schema.sql; дублируем CREATE по конвенции init_db для старых БД).
        #    Начисление — только туда, challenge_scores больше не смешивается.
        # Решение по prod-строкам (идемпотентно, forward-only): точки старых
        # дней постфактум не раздельны (vein +2, challenge +1 в одной сумме),
        # но строку-создателя различаем по first_at: _score_challenge пишет
        # явный isoformat (разделитель 'T'), а vein-путь — sqlite
        # datetime('now') (пробел). Ход миграции:
        #   * first_at с 'T' — строка из challenge-канала: completed_at :=
        #     first_at (реальные выполнения не теряют won);
        #   * иначе — vein/смешанная строка: completed_at остаётся NULL. Это
        #     ровно те игроки, которым won НЕ был выдан из-за бага — при первом
        #     настоящем выполнении цели сегодня он его получит (корректно);
        #   * my_points_total до деплоя включает vein-очки в challenge_scores:
        #     не вычитаем — они были выданы по действовавшим правилам, изъятие
        #     хуже погрешности в большую сторону. С суток деплоя каналы чистые.
        conn.execute(
            """CREATE TABLE IF NOT EXISTS vein_points (
                   day TEXT NOT NULL,
                   device_id TEXT NOT NULL,
                   nick TEXT NOT NULL,
                   points INTEGER NOT NULL DEFAULT 0,
                   first_at TEXT DEFAULT (datetime('now')),
                   PRIMARY KEY (day, device_id)
               )"""
        )
        conn.execute("""CREATE TABLE IF NOT EXISTS personal_discoveries (
            device_id TEXT NOT NULL,
            pair_key TEXT NOT NULL,
            discovered_at TEXT NOT NULL,
            PRIMARY KEY (device_id, pair_key)
        )""")
        conn.execute("""CREATE TABLE IF NOT EXISTS vein_pour_log (
            device_id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL,
            processed_at TEXT NOT NULL,
            PRIMARY KEY (device_id, idempotency_key)
        )""")
        conn.execute("""CREATE TABLE IF NOT EXISTS vein_streaks (
            device_id TEXT NOT NULL, cycle_id TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0, last_hit_at TEXT,
            cap_claimed INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (device_id, cycle_id)
        )""")
        # F2 (по конвенции init_db для старых БД, дубль см. в schema.sql):
        # частичный UNIQUE — не более одного открытого (active/spread) цикла.
        # Константа-ключ: все подходящие строки делят один ключ индекса.
        # Heal: БД, созданная кодом этой ветки ДО появления индекса, может
        # содержать два открытых цикла (гонка _ensure_active_cycle) —
        # иначе CREATE INDEX уронит весь init_db. Оставляем новнейший,
        # прочее закрываем.
        try:
            conn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS ux_vein_cycles_one_open "
                "ON vein_cycles(1) WHERE state IN ('active', 'spread')"
            )
        except sqlite3.IntegrityError:
            newest = conn.execute(
                "SELECT cycle_id FROM vein_cycles "
                "WHERE state IN ('active', 'spread') "
                "ORDER BY started_at DESC LIMIT 1"
            ).fetchone()
            conn.execute(
                "UPDATE vein_cycles SET state='closed', ended_at=? "
                "WHERE state IN ('active', 'spread') AND cycle_id != ?",
                (_now_iso(), newest["cycle_id"]),
            )
            conn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS ux_vein_cycles_one_open "
                "ON vein_cycles(1) WHERE state IN ('active', 'spread')"
            )
        # Migration: old vein_hits(week, device_id) → legacy_vein_hits
        # New vein_hits uses (device_id, cycle_id, pair_key) for anti-farm.
        old_vh_cols = {r["name"] for r in conn.execute("PRAGMA table_info(vein_hits)").fetchall()}
        if "week" in old_vh_cols and "cycle_id" not in old_vh_cols:
            conn.execute("""CREATE TABLE IF NOT EXISTS legacy_vein_hits (
                week TEXT NOT NULL, device_id TEXT NOT NULL,
                count INTEGER NOT NULL DEFAULT 0, streaks INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (week, device_id)
            )""")
            conn.execute("INSERT OR IGNORE INTO legacy_vein_hits SELECT * FROM vein_hits")
            conn.execute("DROP TABLE vein_hits")
            conn.execute("""CREATE TABLE vein_hits (
                device_id TEXT NOT NULL, cycle_id TEXT NOT NULL, pair_key TEXT NOT NULL,
                hit_at TEXT NOT NULL,
                PRIMARY KEY (device_id, cycle_id, pair_key)
            )""")
        scols = {r["name"] for r in conn.execute("PRAGMA table_info(challenge_scores)").fetchall()}
        if "completed_at" not in scols:
            conn.execute("ALTER TABLE challenge_scores ADD COLUMN completed_at TEXT")
            conn.execute(
                "UPDATE challenge_scores SET completed_at = first_at "
                "WHERE completed_at IS NULL AND first_at LIKE '%T%'"
            )

        # Стартовый граф: 57 веществ / 53 рецепта из локальной игры
        seed.seed_db(conn)
        seed.seed_bots(conn)
        # backfill name_norm (дедупликация имён) для строк старых БД
        for r in conn.execute("SELECT id, name FROM elements WHERE name_norm IS NULL").fetchall():
            conn.execute("UPDATE elements SET name_norm = ? WHERE id = ?",
                         (seed.norm_name(r["name"]), r["id"]))
        conn.execute("UPDATE elements SET glyph = slug WHERE glyph = ''")
        # v30: backfill тегов (сиды — по карте, чужие/LLM-строки — из категории)
        for r in conn.execute("SELECT id, slug, category FROM elements WHERE tag = ''").fetchall():
            conn.execute("UPDATE elements SET tag = ? WHERE id = ?",
                         (seed.tag_for(r["slug"], r["category"]), r["id"]))
        # схлопнуть существующие дубли по name_norm (напр. два «огонь» из старых
        # версий): оставляем строку с наименьшим id, перенаправляем ссылки рецептов
        _merge_duplicate_elements(conn)
        # индекс по name_norm создаём только здесь: на старых БД колонка появляется
        # в миграции выше, а не в исходной схеме
        conn.execute("CREATE INDEX IF NOT EXISTS idx_elements_name_norm ON elements(name_norm)")
        # v24: таблица отголосков + индексы для родословной (безопасно для старых БД:
        # CREATE TABLE/INDEX IF NOT EXISTS)
        conn.execute(
            """CREATE TABLE IF NOT EXISTS echoes (
                   device_id TEXT NOT NULL PRIMARY KEY,
                   balance INTEGER NOT NULL DEFAULT 0,
                   total INTEGER NOT NULL DEFAULT 0,
                   last_apprentice_day TEXT
               )"""
        )
        # T03: дедуп резонанса — одна строка на (pair_key, brewer_key) на всё
        # время. Идемпотентно для старых БД (создаётся при первом init_db()).
        conn.execute(
            """CREATE TABLE IF NOT EXISTS resonance_seen (
                   pair_key TEXT NOT NULL,
                   brewer_key TEXT NOT NULL,
                   first_at TEXT DEFAULT (datetime('now')),
                   PRIMARY KEY (pair_key, brewer_key)
               )"""
        )
        # Experiment Bench: durable per-device and global LLM budgets. Existing
        # world/discovery tables remain untouched, so old servers migrate safely.
        conn.execute(
            """CREATE TABLE IF NOT EXISTS experiment_limits (
                   day TEXT NOT NULL,
                   device_id TEXT NOT NULL,
                   attempts INTEGER NOT NULL DEFAULT 0,
                   last_at REAL NOT NULL DEFAULT 0,
                   PRIMARY KEY (day, device_id)
               )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS experiment_global_limits (
                   day TEXT NOT NULL PRIMARY KEY,
                   attempts INTEGER NOT NULL DEFAULT 0
               )"""
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_experiment_limits_device ON experiment_limits(device_id)")
        # Письма: отдельный дневной бюджет LLM-вызовов (пер-девайс + мировой).
        conn.execute(
            """CREATE TABLE IF NOT EXISTS letter_limits (
                   day TEXT NOT NULL,
                   device_id TEXT NOT NULL,
                   attempts INTEGER NOT NULL DEFAULT 0,
                   last_at REAL NOT NULL DEFAULT 0,
                   PRIMARY KEY (day, device_id)
               )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS letter_global_limits (
                   day TEXT NOT NULL PRIMARY KEY,
                   attempts INTEGER NOT NULL DEFAULT 0
               )"""
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_letter_limits_device ON letter_limits(device_id)")
        # Атлас: дневной бюджет LLM-вызовов генерации страницы (мировой ключ "").
        conn.execute(
            """CREATE TABLE IF NOT EXISTS atlas_limits (
                   day TEXT NOT NULL,
                   device_id TEXT NOT NULL,
                   attempts INTEGER NOT NULL DEFAULT 0,
                   last_at REAL NOT NULL DEFAULT 0,
                   PRIMARY KEY (day, device_id)
               )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS atlas_global_limits (
                   day TEXT NOT NULL PRIMARY KEY,
                   attempts INTEGER NOT NULL DEFAULT 0
               )"""
        )
        conn.execute(

            """CREATE TABLE IF NOT EXISTS letters (
                   device_id TEXT NOT NULL,
                   day TEXT NOT NULL,
                   a TEXT NOT NULL,
                   b TEXT NOT NULL,
                   a_name TEXT NOT NULL,
                   b_name TEXT NOT NULL,
                   hint TEXT NOT NULL DEFAULT '',
                   solved INTEGER NOT NULL DEFAULT 0,
                   created_at TEXT DEFAULT (datetime('now')),
                   PRIMARY KEY (device_id, day)
               )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS atlas_pages (
                   day TEXT PRIMARY KEY,
                   a TEXT NOT NULL,
                   b TEXT NOT NULL,
                   a_name TEXT NOT NULL,
                   b_name TEXT NOT NULL,
                   riddle TEXT NOT NULL DEFAULT '',
                   created_at TEXT DEFAULT (datetime('now'))
               )"""
        )
        conn.execute(
            """CREATE TABLE IF NOT EXISTS atlas_solves (
                   device_id TEXT NOT NULL,
                   day TEXT NOT NULL,
                   PRIMARY KEY (device_id, day)
               )"""
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_atlas_solves_device ON atlas_solves(device_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_recipes_a_id ON recipes(a_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_recipes_b_id ON recipes(b_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_elements_author ON elements(author)")
        # T22: журнал чеков (см. /api/receipt/verify). Сырой токен не храним —
        # только SHA-256 (receipt_hash). status: pending — чек увидели, но
        # магазин его не подтвердил; processed — магазин подтвердил, повторный
        # запрос отдаёт тот же ответ без нового обращения в магазин.
        # time.time()-эпохи (T06): от TZ не зависят, с дневными ключами не
        # сравниваются — audit.
        conn.execute(
            """CREATE TABLE IF NOT EXISTS receipts (
                   receipt_hash TEXT PRIMARY KEY,
                   device_id TEXT NOT NULL,
                   provider TEXT NOT NULL,
                   sku TEXT NOT NULL,
                   status TEXT NOT NULL DEFAULT 'pending',
                   first_seen_at REAL NOT NULL,
                   processed_at REAL,
                   last_seen_at REAL NOT NULL
               )"""
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_receipts_device ON receipts(device_id)")
        # T02: авторство по device_id + players.nick UNIQUE (миграция старых БД,
        # идемпотентна: PRAGMA-проверки колонок/индексов, дедуп по суффиксу).
        _migrate_nick_identity(conn)
        conn.commit()
    finally:
        conn.close()


def _migrate_nick_identity(conn: sqlite3.Connection) -> None:
    """Миграция идентичности (T02/T07). Идемпотентна, вызывается из init_db().

    1. elements.author_device / recipes.discoverer_device — экономически
       значимые связи (резонанс, export, delete) ключуются по device_id,
       nick остаётся витриной.
    2. players.nick: разрешение исторических коллизий (двойники, нажитые
       прежним «UPDATE nick на любом запросе») + UNIQUE-индекс. Nick при
       переименовании получает детерминированный суффикс по sha256(device_id).
    3. Backfill author_device/discoverer_device для легаси-строк по нику
       (первый владелец ника = минимальный id). Строки, где автор уже удалён,
       остаются с NULL — для них в коде сохранён fallback по nick.
    4. recipes.linked (T28/I-2): флаг «дедупа имени» для публичных счётчиков.
    """
    ecols = {r["name"] for r in conn.execute("PRAGMA table_info(elements)").fetchall()}
    if "author_device" not in ecols:
        conn.execute("ALTER TABLE elements ADD COLUMN author_device TEXT")
    rcols = {r["name"] for r in conn.execute("PRAGMA table_info(recipes)").fetchall()}
    if "discoverer_device" not in rcols:
        conn.execute("ALTER TABLE recipes ADD COLUMN discoverer_device TEXT")
    # T28 (I-2): «reused ≠ первооткрытие» должно распространяться и на славу:
    # _link_existing вписывает рецепт с discoverer=ник, и hall-of-fame/rating
    # считали такие строки наравне с настоящими первооткрытиями. linked=1 —
    # только у ветки дедупа; обычный create остаётся на дефолте 0. Честно о
    # пределах миграции: строки, на_linked'анные до этого деплоя, останутся с
    # linked=0 — различить created/linked задним числом нечем (gen_method в
    # таблицы не пишется), то есть история до миграции размывается в «созданные».
    if "linked" not in rcols:
        conn.execute("ALTER TABLE recipes ADD COLUMN linked INTEGER NOT NULL DEFAULT 0")

    # (2) переименовать дубли: ник сохраняет «оригинал» — живой игрок важнее
    # бота, среди равных — минимальный id; остальные получают nick-<hash4>.
    for d in conn.execute(
        "SELECT nick FROM players GROUP BY nick HAVING COUNT(*) > 1"
    ).fetchall():
        nick = d["nick"]
        rivals = conn.execute(
            "SELECT id, device_id FROM players WHERE nick = ? "
            "ORDER BY device_id LIKE 'bot-%', id",
            (nick,),
        ).fetchall()
        for r in rivals[1:]:
            # тот же механизм суффикса, что и при регистрации нового устройства
            candidate = _uniquify_nick(conn, nick, r["device_id"])
            conn.execute(
                "UPDATE players SET nick = ? WHERE id = ?", (candidate, r["id"])
            )

    idx = {
        r["name"]: r for r in conn.execute("PRAGMA index_list(players)").fetchall()
    }
    cur = idx.get("idx_players_nick")
    if cur is not None and not cur["unique"]:
        conn.execute("DROP INDEX idx_players_nick")
    conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_players_nick ON players(nick)")

    # (3) backfill авторства по device — только для строк без device-ключа
    conn.execute(
        """UPDATE elements SET author_device =
               (SELECT p.device_id FROM players p
                 WHERE p.nick = elements.author ORDER BY p.id LIMIT 1)
           WHERE author_device IS NULL AND author IS NOT NULL AND author <> ''
             AND EXISTS (SELECT 1 FROM players p2 WHERE p2.nick = elements.author)"""
    )
    conn.execute(
        """UPDATE recipes SET discoverer_device =
               (SELECT p.device_id FROM players p
                 WHERE p.nick = recipes.discoverer ORDER BY p.id LIMIT 1)
           WHERE discoverer_device IS NULL
             AND discoverer IS NOT NULL AND discoverer <> ''
             AND EXISTS (SELECT 1 FROM players p2 WHERE p2.nick = recipes.discoverer)"""
    )


def _merge_duplicate_elements(conn: sqlite3.Connection) -> None:
    """Схлопнуть дубли элементов с одинаковым name_norm (напр. «Огонь» и «огонь» из
    старых версий). Оставляем строку с наименьшим id, ссылки рецептов (a_id/b_id/
    out_id) перенаправляем на неё, дубликаты удаляем."""
    dups = conn.execute(
        "SELECT name_norm, COUNT(*) AS n FROM elements "
        "WHERE name_norm IS NOT NULL AND name_norm != '' "
        "GROUP BY name_norm HAVING n > 1"
    ).fetchall()
    for d in dups:
        rows = conn.execute(
            "SELECT id FROM elements WHERE name_norm = ? ORDER BY id", (d["name_norm"],)
        ).fetchall()
        keep_id = rows[0]["id"]
        for r in rows[1:]:
            drop_id = r["id"]
            conn.execute("UPDATE recipes SET a_id = ? WHERE a_id = ?", (keep_id, drop_id))
            conn.execute("UPDATE recipes SET b_id = ? WHERE b_id = ?", (keep_id, drop_id))
            conn.execute("UPDATE recipes SET out_id = ? WHERE out_id = ?", (keep_id, drop_id))
            conn.execute("DELETE FROM elements WHERE id = ?", (drop_id,))


def reset_world(conn: sqlite3.Connection) -> None:
    """Полный сброс первооткрытий: удалить все элементы, рецепты, отказы и
    блокировки, затем заново загрузить чистый стартовый граф (57 веществ /
    53 рецепта). Нужно, чтобы вычистить результаты старой логики генерации
    (например, имена из удалённых «пулов»)."""
    conn.execute("DELETE FROM recipes")
    conn.execute("DELETE FROM elements")
    conn.execute("DELETE FROM rejected_pairs")
    conn.execute("DELETE FROM pending_pairs")
    conn.execute("DELETE FROM echoes")
    seed.seed_db(conn)
    seed.seed_bots(conn)
    conn.execute("UPDATE elements SET glyph = slug WHERE glyph = ''")

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Хеш-функция для детерминированных решений (слаг, цвет)
# ---------------------------------------------------------------------------
def _hash_to_int(s: str, mod: int) -> int:
    """Определённая хеш-функция строки в [0, mod)."""
    h = int(hashlib.sha256(s.encode("utf-8")).hexdigest(), 16)
    return h % mod

# Палитра аватаров (10 цветов) — совпадает с game/avatar.gd на клиенте.
# Палитра построена по цветовому кругу (10 оттенков через 36°, S≈0.47/V≈0.80) —
# совпадает с game/avatar.gd на клиенте.
AVATAR_PALETTE = [
    "#cc6c6c", "#cca66c", "#b9cc6c", "#7fcc6c", "#6ccc92",
    "#6ccccc", "#6c92cc", "#7f6ccc", "#b96ccc", "#cc6ca6",
]

def avatar_for(seed: str) -> dict:
    """Детерминированный процедурный аватар из строки-сида (ник игрока).

    Клиент (game/avatar.gd) реализует ТОТ ЖЕ алгоритм, поэтому аватар,
    посчитанный сервером, совпадает с локальной отрисовкой. Возвращает
    словарь {bg, accent, sym, ring}: цвета из палитры, индекс символа 0..11,
    флаг внешнего кольца.
    """
    h = hashlib.sha256(("avatar_" + (seed or "")).encode("utf-8")).digest()
    bg_idx = h[0] % len(AVATAR_PALETTE)
    # split-complementary: акцент на 4..6 позиций (144°..180°) от фона,
    # чтобы символ/кольцо контрастировали и не сливались с фоном.
    accent_idx = (bg_idx + 4 + h[1] % 3) % len(AVATAR_PALETTE)
    sym = h[2] % 12
    ring = bool(h[3] & 1)
    return {
        "bg": AVATAR_PALETTE[bg_idx],
        "accent": AVATAR_PALETTE[accent_idx],
        "sym": sym,
        "ring": ring,
    }

def clean_nick(raw: str) -> str:
    """Нормализация ника: обрезка, схлопывание пробелов, только буквы/цифры/
    пробел/дефис/подчёркивание, длина 2..24. Пустое/невалидное -> ""."""
    if not raw:
        return ""
    s = str(raw)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"[^\w\s\-]", "", s, flags=re.UNICODE)
    s = re.sub(r"\s+", " ", s).strip()
    if len(s) < 2 or len(s) > 24:
        return ""
    return s

def slugify(name: str) -> str:
    """Преобразование русского имени в латинский слаг."""
    # Транслитерация базовых символов
    replacements = {
        'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
        'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
        'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
        'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
        'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
        'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '',
        'э': 'e', 'ю': 'yu', 'я': 'ya',
    }
    slug = ""
    for ch in name.lower():
        if ch in replacements:
            slug += replacements[ch]
        elif ch.isalnum():
            slug += ch.lower()
        elif ch in "-_":
            slug += ch
        else:
            slug += "-"
    # Убираем повторяющиеся дефисы и обрезаем
    slug = re.sub(r"-+", "-", slug).strip("-")
    slug = re.sub(r"[^a-z0-9-]", "", slug)
    slug = re.sub(r"-+", "-", slug).strip("-")
    if not slug:
        return "element"
    # T07: канонизация под _SLUG_PATTERN (server.py: BrewCheckRequest.a/b):
    # не длиннее 64 символов, начинается с [a-z0-9].
    slug = slug[:_SLUG_MAX_LEN].rstrip("-")
    if not slug or not re.match(r"^[a-z0-9]", slug):
        slug = slug[1:] if slug else ""
    return slug or "element"

# Предельная длина слага: совпадает с max_length/pattern a/b (BrewCheckRequest).
_SLUG_MAX_LEN = 64

def _slug_with_suffix(base: str, suffix: str) -> str:
    """base+suffix с гарантией вписывания в _SLUG_MAX_LEN (основа усекается
    по границе дефиса, чтобы результат остался валидным слагом)."""
    cand = base + suffix
    if len(cand) <= _SLUG_MAX_LEN:
        return cand
    trimmed = base[: _SLUG_MAX_LEN - len(suffix)].rstrip("-") or "el"
    return trimmed + suffix

def generate_slug(name: str, pair_key: str, existing_slugs: set[str]) -> str:
    """Генерация уникального слага (результат всегда <= 64 символов и
    соответствует _SLUG_PATTERN — T07)."""
    base_slug = slugify(name)

    if base_slug not in existing_slugs:
        return base_slug

    # При коллизии добавляем суффикс по hash(pair_key) — с усечением основы,
    # чтобы итог не вылез за лимит модели запроса.
    hash_int = _hash_to_int(pair_key, 997)
    counter = 1
    while True:
        candidate = _slug_with_suffix(base_slug, f"-{counter}")
        if candidate not in existing_slugs:
            return candidate
        candidate = _slug_with_suffix(base_slug, str(hash_int))
        if candidate not in existing_slugs:
            return candidate
        counter += 1
        if counter > 10:
            # Фантастический случай — добавляем UUID-суффикс
            return _slug_with_suffix(base_slug, f"-{uuid.uuid4().hex[:6]}")

def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Преобразование #RRGGBB в (R, G, B)."""
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Преобразование (R, G, B) в #RRGGBB."""
    return f"#{r:02x}{g:02x}{b:02x}"

def color_distance(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    """Euclidean distance в RGB."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))

def mix_colors(
    color_a: str,
    color_b: str,
    layer_a: int,
    layer_b: int,
    pair_key: str,
    existing_colors: set[str],
) -> str:
    """
    Детерминированная смесь цветов родителей.

    Вес = 1 + layer/10 (более глубокие элементы сильнее влияют на цвет).
    Результат обязан отличаться от обоих родителей (мин. 32 ед. RGB) и,
    по возможности, от уже существующих цветов. При несоответствии —
    детерминированный сдвиг (LCG по hash(pair_key)).
    """
    r_a, g_a, b_a = hex_to_rgb(color_a)
    r_b, g_b, b_b = hex_to_rgb(color_b)

    w_a = 1.0 + layer_a / 10.0
    w_b = 1.0 + layer_b / 10.0

    r = round((r_a * w_a + r_b * w_b) / (w_a + w_b))
    g = round((g_a * w_a + g_b * w_b) / (w_a + w_b))
    b = round((b_a * w_a + b_b * w_b) / (w_a + w_b))

    new = (r, g, b)
    seed = _hash_to_int(pair_key, 10000)

    for _ in range(24):
        new_hex = rgb_to_hex(*new)
        dist_a = color_distance(new, (r_a, g_a, b_a))
        dist_b = color_distance(new, (r_b, g_b, b_b))
        if min(dist_a, dist_b) >= 32 and new_hex not in existing_colors:
            return new_hex
        # Детерминированный сдвиг (LCG), чтобы уйти от родительских цветов.
        seed = (seed * 1103515245 + 12345) % (2**31)
        new = (
            max(0, min(255, r + (seed % 51) - 25)),
            max(0, min(255, g + ((seed // 51) % 51) - 25)),
            max(0, min(255, b + ((seed // 2601) % 51) - 25)),
        )

    return rgb_to_hex(*new)


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Недельный слой (v30): туманная жила + ярмарка гильдии
# ---------------------------------------------------------------------------

VEIN_POINTS = 2          # очков дня за первооткрытие в жиле
VEIN_STREAK_CHANCE = 0.10  # шанс прожилки (+1 кап на клиенте)
VEIN_STREAK_CAP = 5      # прожилок в неделю на устройство
FAIR_MIN_CONTRIB = 3     # вклад для награды регеном при закрытом котле
FAIR_CONSOLATION = 30    # эфира за 1 вклад при незакрытом котле
FAIR_CONSOLATION_CAP = 20  # потолок вкладов для утешения


def _week_key(day=None) -> str:
    from datetime import date as _date
    d = _date.fromisoformat(day) if isinstance(day, str) else (day or _today_date())
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


def _week_monday(week: str):
    from datetime import date as _date
    y, w = week.split("-W")
    return _date.fromisocalendar(int(y), int(w), 1)


def _week_tags(conn: sqlite3.Connection) -> list:
    tags = [r["tag"] for r in conn.execute(
        "SELECT DISTINCT tag FROM elements WHERE tag != '' ORDER BY tag").fetchall()]
    return tags or sorted(TAGS)


def _week_pick(salt: str, week: str, tags: list) -> str:
    i = int(hashlib.sha256((salt + week).encode("utf-8")).hexdigest(), 16) % len(tags)
    return tags[i]


def _vein_state(conn: sqlite3.Connection, week: str, today=None):
    """Теги жилы недели + расползся ли туман (0 находок к среде → второй тег).
    today по умолчанию — сегодня в ЕДИНОЙ серверной шкале (T06)."""
    tags = _week_tags(conn)
    tag1 = _week_pick("vein1_", week, tags)
    tag2 = _week_pick("vein2_", week, tags)
    if tag2 == tag1 and len(tags) > 1:
        tag2 = tags[(tags.index(tag1) + 1) % len(tags)]
    monday = _week_monday(week).isoformat()
    hits = conn.execute(
        "SELECT COUNT(*) AS c FROM recipes r JOIN elements e ON r.out_id = e.id "
        "WHERE e.tag = ? AND date(r.created_at) >= date(?) AND r.discoverer IS NOT NULL "
        # (#17) Бот-атрибуция стартового графа — не находка живых игроков:
        # свежая БД с seed-строками created_at=сегодня не должна «расползать»
        # туман жилы без единого реального открытия.
        "AND COALESCE(r.discoverer_device, '') NOT LIKE 'bot-%'",
        (tag1, monday),
    ).fetchone()["c"]
    day = today or _today_date()
    spread = hits == 0 and day.weekday() >= 2
    return tag1, tag2, spread


def _fair_ensure(conn: sqlite3.Connection, week: str) -> dict:
    row = conn.execute("SELECT * FROM fair_weeks WHERE week = ?", (week,)).fetchone()
    if row:
        return dict(row)
    tags = _week_tags(conn)
    tag = _week_pick("fair_", week, tags)
    since = (_week_monday(week) - timedelta(days=6)).isoformat()
    # T06: last_seen пишется тем же _today() (единая шкала), поэтому сравнение
    # с date(since) честно: обе стороны — календарные сутки сервера.
    active7 = conn.execute(
        "SELECT COUNT(*) AS c FROM players WHERE last_seen IS NOT NULL AND last_seen >= date(?)",
        (since,),
    ).fetchone()["c"]
    active7 = max(int(active7), 1)
    goal = max(10, round(3 * active7 * 1.5))
    conn.execute("INSERT INTO fair_weeks (week, tag, goal, progress) VALUES (?, ?, ?, 0)",
                 (week, tag, goal))
    conn.commit()
    return {"week": week, "tag": tag, "goal": goal, "progress": 0}


def _fair_virtual(progress: int, goal: int, days_elapsed: int) -> int:
    # подмастерья гильдии доваривают 10% цели в день (на чтении, не в БД)
    return progress + int(goal * 0.1 * min(max(days_elapsed, 0), 7))


def _add_vein_points(conn: sqlite3.Connection, day: str, device_id: str, nick: str, pts: int) -> None:
    """Vein-канал (U6/T05): очки жилы живут в vein_points, а не в
    challenge_scores — строка в дневном счёте означает только «цель дня
    выполнена» и участвует в completions/won."""
    conn.execute(
        """INSERT INTO vein_points (day, device_id, nick, points)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(day, device_id) DO UPDATE SET
             points = points + excluded.points, nick = excluded.nick""",
        (day, device_id, nick, pts),
    )


VEIN_SPREAD_THRESHOLD = 20
VEIN_MAX_CYCLE_DAYS = 14
VEIN_SPREAD_DURATION = 3


def _cycle_pick(conn: sqlite3.Connection, exclude: list[str] | None = None) -> str:
    """Pick a tag for a new cycle, excluding tags from last 2 cycles + explicit excludes."""
    tags = _week_tags(conn)
    recent = conn.execute(
        "SELECT tag1, tag2 FROM vein_cycles ORDER BY started_at DESC LIMIT 2"
    ).fetchall()
    excluded = set(exclude or [])
    for row in recent:
        if row["tag1"]:
            excluded.add(row["tag1"])
        if row["tag2"]:
            excluded.add(row["tag2"])
    candidates = [t for t in tags if t not in excluded]
    if not candidates:
        candidates = tags  # fallback if all excluded
    import hashlib as _hl
    salt = f"cycle_{len(conn.execute('SELECT 1 FROM vein_cycles').fetchall())}"
    i = int(_hl.sha256(salt.encode()).hexdigest(), 16) % len(candidates)
    return candidates[i]


def _ensure_active_cycle(conn: sqlite3.Connection) -> dict:
    """Ensure an active cycle exists. Creates one if none is active or spread.
    Returns the current active/spread cycle as a dict."""
    row = conn.execute(
        "SELECT * FROM vein_cycles WHERE state IN ('active', 'spread') "
        "ORDER BY started_at DESC LIMIT 1"
    ).fetchone()
    if row:
        return dict(row)
    tag1 = _cycle_pick(conn)
    # uuid-суффикс: цикл может быть закрыт и пересоздан в ту же секунду
    # (например, в /api/vein/cycle/status expiry-переходе) — чистый unix-ts
    # дал бы коллизию PRIMARY KEY.
    cycle_id = f"vc:{int(time.time())}-{uuid.uuid4().hex[:6]}"
    now = _now_iso()
    try:
        conn.execute(
            "INSERT INTO vein_cycles (cycle_id, started_at, tag1, state, spread_threshold) "
            "VALUES (?, ?, ?, 'active', ?)",
            (cycle_id, now, tag1, VEIN_SPREAD_THRESHOLD),
        )
    except sqlite3.IntegrityError:
        # F2 (гонка): ux_vein_cycles_one_open — между пустым SELECT выше и
        # этим INSERT конкурент успел создать (и закоммитить) открытый цикл.
        # Возвращаем его ряд в той же dict-форме, что и обычный путь.
        row = conn.execute(
            "SELECT * FROM vein_cycles WHERE state IN ('active', 'spread') "
            "ORDER BY started_at DESC LIMIT 1"
        ).fetchone()
        if row is None:
            raise
        return dict(row)
    return {
        "cycle_id": cycle_id, "started_at": now, "ended_at": None,
        "spread_at": None, "tag1": tag1, "tag2": None,
        "state": "active", "spread_threshold": VEIN_SPREAD_THRESHOLD,
        "world_finds": 0,
    }


def _maybe_spread_cycle(conn: sqlite3.Connection, cycle: dict) -> None:
    """CAS transition active→spread if threshold reached or max days elapsed.

    Re-читает строку цикла из БД: инкремент world_finds, сделанный
    _score_vein_cycle в ЭТОМ ЖЕ соединении/транзакции, виден только так
    (снимка-аргумент устарел). Мутит переданный dict, чтобы вызывающий
    увидел свежий state/tag2.
    """
    fresh = conn.execute(
        "SELECT * FROM vein_cycles WHERE cycle_id = ?", (cycle["cycle_id"],)
    ).fetchone()
    if fresh is None:
        return
    cycle.update(dict(fresh))
    if cycle["state"] != "active":
        return
    started = date.fromisoformat(cycle["started_at"][:10])
    days_elapsed = (_today_date() - started).days
    needs_spread = (
        cycle["world_finds"] >= cycle["spread_threshold"]
        or days_elapsed >= VEIN_MAX_CYCLE_DAYS
    )
    if not needs_spread:
        return
    tag2 = _cycle_pick(conn, exclude=[cycle["tag1"]])
    now = _now_iso()
    cursor = conn.execute(
        "UPDATE vein_cycles SET state='spread', tag2 = ?, spread_at = ? "
        "WHERE cycle_id = ? AND state='active'",
        (tag2, now, cycle["cycle_id"]),
    )
    if cursor.rowcount == 0:
        # Другой запрос уже перевёл цикл: перечитать tag2, state не трогаем.
        updated = conn.execute(
            "SELECT tag2 FROM vein_cycles WHERE cycle_id = ?", (cycle["cycle_id"],)
        ).fetchone()
        if updated:
            cycle["tag2"] = updated["tag2"]
    else:
        cycle["tag2"] = tag2
        cycle["state"] = "spread"
        cycle["spread_at"] = now


def _score_vein_cycle(conn: sqlite3.Connection, cycle: dict, tag: str,
                      pair_key: str, device_id: str, nick: str,
                      is_world_first: bool) -> dict | None:
    """Transactional vein scorer for cycle-based model.

    Returns {points, streak_added, streak_count, cap_reached} or None if
    tag doesn't match or pair already hit this cycle.

    Must be called inside a transaction that also commits the discover/find.
    """
    active_tags = {cycle["tag1"]}
    if cycle["tag2"]:
        active_tags.add(cycle["tag2"])
    if tag not in active_tags:
        return None

    cycle_id = cycle["cycle_id"]

    # Anti-farm: pair already scored this cycle?
    existing = conn.execute(
        "SELECT 1 FROM vein_hits WHERE device_id=? AND cycle_id=? AND pair_key=?",
        (device_id, cycle_id, pair_key),
    ).fetchone()
    if existing:
        return None

    # Record hit
    conn.execute(
        "INSERT INTO vein_hits (device_id, cycle_id, pair_key, hit_at) VALUES (?, ?, ?, ?)",
        (device_id, cycle_id, pair_key, _now_iso()),
    )

    # Points: world-first=VEIN_POINTS, personal=1
    points = VEIN_POINTS if is_world_first else 1  # личные находки: всегда 1 (спека §3.1)

    # Day points (existing vein_points channel)
    day = _today()
    if device_id:
        _add_vein_points(conn, day, device_id, nick, points)

    # Increment world_finds if world-first
    if is_world_first:
        conn.execute(
            "UPDATE vein_cycles SET world_finds = world_finds + 1 WHERE cycle_id = ?",
            (cycle_id,),
        )

    # Streak logic
    streak_added = False
    cap_reached = False
    streak_row = conn.execute(
        "SELECT count, cap_claimed FROM vein_streaks WHERE device_id=? AND cycle_id=?",
        (device_id, cycle_id),
    ).fetchone()
    cur_count = streak_row["count"] if streak_row else 0
    cap_claimed = bool(streak_row["cap_claimed"]) if streak_row else False

    if not cap_claimed:
        if is_world_first:
            streak_added = True
        else:
            streak_added = random.random() < VEIN_STREAK_CHANCE
            if not streak_added:
                # §3.1.2: при неудачном roll streak сбрасывается в 0. Reset
                # только здесь — на проигрышном ролле scoring-находки;
                # wrong-tag/anti-farm ранние выходы (§6 п.4) не трогают streak.
                cur_count = 0

        if streak_added:
            cur_count += 1

        if cur_count >= VEIN_STREAK_CAP:
            cap_reached = True
            cap_claimed = True
            cur_count = 0  # reset count, but cap_claimed stays

    conn.execute(
        """INSERT INTO vein_streaks (device_id, cycle_id, count, last_hit_at, cap_claimed)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(device_id, cycle_id) DO UPDATE SET
             count = excluded.count, last_hit_at = excluded.last_hit_at,
             cap_claimed = excluded.cap_claimed""",
        (device_id, cycle_id, cur_count, _now_iso(), int(cap_claimed)),
    )

    return {
        "points": points,
        "streak_added": streak_added,
        "streak_count": cur_count,
        "cap_reached": cap_reached,
    }


# API-endpoints
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def startup():
    """Инициализация БД при старте."""
    init_db()
    # T08.2: зачистка старых «могил» pending_pairs (state='resolved' из-под
    # прежней логики и протухшие блокировки). Новая логика их не создаёт:
    # лок снимается DELETE-ом. Если процесс умер посреди генерации —
    # протухший лок здесь снимается, пара снова становится кандидатом.
    conn = get_db()
    try:
        conn.execute("DELETE FROM pending_pairs WHERE state != 'locked'")
        conn.execute(
            "DELETE FROM pending_pairs WHERE lock_ts <= ?", (time.time() - LOCK_TTL,)
        )
        # T22: журнал чеков пополняется каждым запросом; о pending-строках,
        # которые не обновлялись 30 суток, клиент уже не вспоминал — это мусор
        # перебора/удалённых установок. processed НЕ чистим: они и есть
        # серверный ответ «этот чек уже подтверждался».
        conn.execute(
            "DELETE FROM receipts WHERE status != 'processed' AND last_seen_at < ?",
            (time.time() - 30 * 86400,),
        )
        conn.commit()
    finally:
        conn.close()
    gen = get_llm()
    prov = getattr(gen, "provider", "?")
    models = ", ".join(getattr(gen, "models", []) or [])
    if prov in ("openrouter", "openai_compatible") and getattr(gen, "api_key", ""):
        print(f"[world] LLM: {prov} (ключ задан) — генерация через модель")
        print(f"[world] Модели: {models}")
    elif prov in ("openrouter", "openai_compatible"):
        print("[world] LLM: нет ключа — задайте OPENROUTER_API_KEY или LLM_API_KEY+LLM_BASE_URL")
    elif prov == "local":
        print("[world] Генерация: локальная (очевидные пары). Для полной LLM задайте ключ.")
    else:
        print(f"[world] LLM-провайдер: {prov}")

    # Подключаем дашборд и админ-панель
    global _dashboard_setup
    if not _dashboard_setup:
        dashboard.setup_dashboard(app, get_db, DB_PATH)
        admin.setup_admin(app, get_db)
        _dashboard_setup = True
        print("[world] Дашборд: /dashboard")
        if os.environ.get("ADMIN_PASS"):
            print("[world] Админ-панель: /admin")
        else:
            print("[world] Админ-панель: /admin (ADMIN_PASS не задан — вход заблокирован)")

@app.get("/api/health", response_model=HealthResponse)
async def health():
    """Проверка доступности сервера."""
    return {"ok": True, "version": "1.0.0"}

def _nick_taken(conn: sqlite3.Connection, nick: str, device_id: str) -> bool:
    """Занят ли ник другим устройством."""
    return conn.execute(
        "SELECT 1 FROM players WHERE nick = ? AND device_id <> ?", (nick, device_id)
    ).fetchone() is not None


def _uniquify_nick(conn: sqlite3.Connection, nick: str, device_id: str) -> str:
    """Ник свободен — он и есть; занят — детерминированный суффикс по
    sha256(device_id) (тот же механизм, что в _migrate_nick_identity),
    со счётчиком при повторной коллизии."""
    if not _nick_taken(conn, nick, device_id):
        return nick
    suffix = hashlib.sha256(device_id.encode("utf-8")).hexdigest()[:4]
    candidate = f"{nick}-{suffix}"
    bump = 1
    while _nick_taken(conn, candidate, device_id):
        candidate = f"{nick}-{suffix}{bump}"
        bump += 1
    return candidate


def _upsert_player(conn: sqlite3.Connection, nick: str, device_id: str) -> str:
    """Зарегистрировать игрока и вернуть его «витринный» ник.

    T02: идентичность — device_id; nick для известного устройства здесь
    НЕ меняется (раньше любой brew-check мог присвоить чужой ник). Переименование
    — только через POST /api/me с проверкой занятости («Ник уже занят»).
    T07: 400 на этом пути — только для НЕ нормализованного ника (clean_nick).
    Валидный, но занятый ник у нового устройства (дефолт клиента «Алхимик»)
    регистрацию НЕ блокирует: устройство заводится с детерминированным
    унифицированным ником, который и возвращается как канонический.
    """
    existing = conn.execute(
        "SELECT nick FROM players WHERE device_id = ?", (device_id,)
    ).fetchone()
    if existing is not None:
        # T06: last_seen — параметр Python (единая шкала), а не SQLite date('now'):
        # иначе на не-UTC хосте окно «7 дней» ярмарки(_fair_ensure) и last_seen
        # жили бы в разных шкалах.
        conn.execute(
            "UPDATE players SET last_seen = ? WHERE device_id = ?",
            (_today(), device_id),
        )
        return existing["nick"]
    cleaned = clean_nick(nick)
    if not cleaned or cleaned != nick:
        raise HTTPException(
            status_code=400,
            detail="Ник должен быть 2–24 символа: буквы, цифры, пробел, дефис или подчёркивание",
        )
    final_nick = nick
    for _ in range(3):
        try:
            conn.execute(
                "INSERT INTO players (nick, device_id, last_seen, created_at) VALUES (?, ?, ?, ?)",
                (final_nick, device_id, _today(), _now_iso()),
            )
            return final_nick
        except sqlite3.IntegrityError:
            # гонка по device_id: система создана параллельным запросом —
            # возвращаем сохранённый ник, а не ошибку «занят»
            row = conn.execute(
                "SELECT nick FROM players WHERE device_id = ?", (device_id,)
            ).fetchone()
            if row is not None:
                return row["nick"]
            # гонка по нику (idx_players_nick): пересчитать унифицированный
            # ник и повторить попытку
            final_nick = _uniquify_nick(conn, nick, device_id)
    raise HTTPException(status_code=503, detail="Не удалось зарегистрировать игрока — повторите попытку")

_LLM_GEN = None


def get_llm() -> "LLMGenerator":
    """Синглтон LLM-генератора (лениво читает env)."""
    global _LLM_GEN
    if _LLM_GEN is None:
        _LLM_GEN = LLMGenerator()
    return _LLM_GEN


def _parent(conn: sqlite3.Connection, slug: str) -> dict:
    row = conn.execute(
        "SELECT id, slug, name, color, layer, category FROM elements WHERE slug = ?",
        (slug,),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=400, detail=f"Ингредиент '{slug}' не найден в базе")
    return {
        "id": row["id"], "slug": row["slug"], "name": row["name"],
        "color": row["color"], "layer": row["layer"], "category": row["category"],
    }


def _result_category(a_info: dict, b_info: dict) -> str:
    if a_info["layer"] > b_info["layer"]:
        return a_info["category"]
    if b_info["layer"] > a_info["layer"]:
        return b_info["category"]
    return b_info["category"]


CATEGORY_GLYPH = {"огонь": "fire", "вода": "water", "земля": "earth", "воздух": "air"}


def _category_glyph(category: str) -> str:
    return CATEGORY_GLYPH.get(category, "")


def _fallback_glyph(name: str, category: str) -> str:
    """Глиф, если модель не дала своего: базовые категории — тематический образ,
    иначе — детерминированный параметрический глиф по имени (уникальный и
    стабильный, не повторяет иконки базовых стихий)."""
    g = _category_glyph(category)
    if g:
        return g
    h = int(hashlib.sha256(("glyph_" + (name or "")).encode("utf-8")).hexdigest(), 16)
    bases = list(GLYPH_PARAM.keys())
    base = bases[h % len(bases)]
    lo, hi = GLYPH_PARAM[base]
    return f"{base}{lo + h % (hi - lo + 1)}"


def _experiment_uses_llm() -> bool:
    """True when a new experiment can spend an external LLM request.

    The local/mock providers are deterministic and do not consume the external
    budget. The off provider will return unavailable without a network call.
    """
    try:
        provider = str(get_llm().provider).strip().lower()
    except Exception:
        return True
    return provider not in ("", "local", "mock", "off")


def _reserve_llm_generation(
    conn: sqlite3.Connection, device_id: str, *, limits_table: str, global_table: str,
    cooldown_sec: float, daily_limit: int, global_daily_limit: int,
    cooldown_msg: str, daily_msg: str, global_msg: str,
) -> tuple[bool, str]:
    """Reserve one external LLM generation for this device/day.

    The database is the source of truth, so restarting the server does not reset
    the per-device quota. A zero global limit disables only the global guard.
    Callers invoke this at the FACT of an LLM call (inside the generators), not
    on a client-supplied flag. Local/mock providers do not spend external
    budget. Cooldown and daily counter are bumped here; a failed (unavailable)
    generation must return the charge via _refund_llm_generation.
    """
    if not _experiment_uses_llm():
        return True, ""
    # T06: cooldown окно — эпоха time.time() (от TZ не зависит, как lock_ts);
    # дневной ключ лимита — _today() (единая шкала). Скачок wall-clock/NTP
    # искажает только кулдаун, не границу дня.
    now = time.time()
    day = _today()
    row = conn.execute(
        f"SELECT attempts, last_at FROM {limits_table} WHERE day = ? AND device_id = ?",
        (day, device_id),
    ).fetchone()
    attempts = int(row["attempts"]) if row else 0
    last_at = float(row["last_at"]) if row else 0.0
    if now - last_at < max(0.0, cooldown_sec):
        wait = max(1, int(math.ceil(cooldown_sec - (now - last_at))))
        return False, cooldown_msg % wait
    if daily_limit > 0 and attempts >= daily_limit:
        return False, daily_msg
    global_row = conn.execute(
        f"SELECT attempts FROM {global_table} WHERE day = ?", (day,)
    ).fetchone()
    global_attempts = int(global_row["attempts"]) if global_row else 0
    if global_daily_limit > 0 and global_attempts >= global_daily_limit:
        return False, global_msg
    conn.execute(
        f"INSERT INTO {limits_table}(day, device_id, attempts, last_at) VALUES (?, ?, 1, ?) "
        "ON CONFLICT(day, device_id) DO UPDATE SET attempts = attempts + 1, last_at = excluded.last_at",
        (day, device_id, now),
    )
    conn.execute(
        f"INSERT INTO {global_table}(day, attempts) VALUES (?, 1) "
        "ON CONFLICT(day) DO UPDATE SET attempts = attempts + 1",
        (day,),
    )
    conn.commit()
    return True, ""


def _refund_llm_generation(
    conn: sqlite3.Connection, device_id: str, *, limits_table: str, global_table: str
):
    """Return a reserved charge when the LLM turned out to be unavailable:
    the quota is spent only on real generations, not on failures.
    last_at stays — the cooldown still guards against hammering a broken LLM."""
    if not _experiment_uses_llm():
        return
    day = _today()
    conn.execute(
        f"UPDATE {limits_table} SET attempts = MAX(attempts - 1, 0) WHERE day = ? AND device_id = ?",
        (day, device_id),
    )
    conn.execute(
        f"UPDATE {global_table} SET attempts = MAX(attempts - 1, 0) WHERE day = ?",
        (day,),
    )
    conn.commit()


class QuotaExceeded(Exception):
    """LLM-квота на сегодня исчерпана (дневной/мировой лимит или кулдаун).
    text — готовое сообщение для клиента (response уже содержит статус
    rate_limited). Поднимается из генераторов, квота резервируется по факту
    обращения к LLM, а не по клиентскому флагу."""

    def __init__(self, text: str):
        super().__init__(text)
        self.text = text


def _admit_experiment(conn: sqlite3.Connection, device_id: str) -> tuple[bool, str]:
    """Reserve one LLM-backed experiment for this device/day (see _reserve...)."""
    return _reserve_llm_generation(
        conn, device_id,
        limits_table="experiment_limits", global_table="experiment_global_limits",
        cooldown_sec=EXPERIMENT_COOLDOWN_SEC, daily_limit=EXPERIMENT_DAILY_LIMIT,
        global_daily_limit=EXPERIMENT_GLOBAL_DAILY_LIMIT,
        cooldown_msg="Эксперимент можно отправить через %d с.",
        daily_msg="Дневной лимит экспериментов исчерпан.",
        global_msg="Мировой лимит экспериментов на сегодня исчерпан.",
    )


def _refund_experiment(conn: sqlite3.Connection, device_id: str):
    _refund_llm_generation(
        conn, device_id,
        limits_table="experiment_limits", global_table="experiment_global_limits",
    )


def _admit_letter(conn: sqlite3.Connection, device_id: str) -> tuple[bool, str]:
    """Reserve one letter-hint LLM generation for this device/day."""
    return _reserve_llm_generation(
        conn, device_id,
        limits_table="letter_limits", global_table="letter_global_limits",
        cooldown_sec=LETTER_COOLDOWN_SEC, daily_limit=LETTER_DAILY_LIMIT,
        global_daily_limit=LETTER_GLOBAL_DAILY_LIMIT,
        cooldown_msg="Письмо можно запросить через %d с.",
        daily_msg="Дневной лимит писем исчерпан.",
        global_msg="Мировой лимит писем на сегодня исчерпан.",
    )


def _refund_letter(conn: sqlite3.Connection, device_id: str):
    _refund_llm_generation(
        conn, device_id,
        limits_table="letter_limits", global_table="letter_global_limits",
    )


ATLAS_QUOTA_KEY = ""  # атлас общемировой: квота на весь сервер под фиксированным ключом


def _admit_atlas(conn: sqlite3.Connection) -> tuple[bool, str]:
    """Reserve one atlas-page LLM generation for today (world-wide budget)."""
    return _reserve_llm_generation(
        conn, ATLAS_QUOTA_KEY,
        limits_table="atlas_limits", global_table="atlas_global_limits",
        cooldown_sec=ATLAS_COOLDOWN_SEC, daily_limit=ATLAS_DAILY_LIMIT,
        global_daily_limit=ATLAS_DAILY_LIMIT,
        cooldown_msg="Страницу атласа можно запросить через %d с.",
        daily_msg="Дневной лимит генераций атласа исчерпан.",
        global_msg="Дневной лимит генераций атласа исчерпан.",
    )


def _refund_atlas(conn: sqlite3.Connection):
    _refund_llm_generation(
        conn, ATLAS_QUOTA_KEY,
        limits_table="atlas_limits", global_table="atlas_global_limits",
    )


def _challenge_target_for(day: str) -> str:
    """Детерминированный целевой ингредиент дня (одинаков для всех игроков)."""
    h = int(hashlib.sha256(("challenge_" + day).encode("utf-8")).hexdigest(), 16)
    return CHALLENGE_TARGETS[h % len(CHALLENGE_TARGETS)]


def _ensure_challenge(conn: sqlite3.Connection) -> dict:
    """Вернуть сегодняшнюю цель (создать, если ещё нет). БД — источник истины.

    T08.3: INSERT OR IGNORE — при параллельном первом создании «дня» двумя
    запросами второй не падает IntegrityError-500, а забирает чужую строку.
    """
    day = _today()
    row = conn.execute("SELECT * FROM challenges WHERE day = ?", (day,)).fetchone()
    if not row:
        target = _challenge_target_for(day)
        trow = conn.execute("SELECT name FROM elements WHERE slug = ?", (target,)).fetchone()
        target_name = trow["name"] if trow else target
        hint = "Вещество, рождённое из «%s»." % target_name
        conn.execute(
            "INSERT OR IGNORE INTO challenges (day, target, target_name, hint, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (day, target, target_name, hint, _now_iso()),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM challenges WHERE day = ?", (day,)).fetchone()
        if not row:  # фантастика: строку удалили между вставкой и чтением
            raise HTTPException(status_code=503, detail="Цель дня не готова — повторите попытку")
    return dict(row)


def _score_challenge(conn: sqlite3.Connection, a: str, b: str, nick: str, device_id: str) -> dict:
    """Личная ежедневная цель после первооткрытия.

    Гонка НЕ закрывается первым победителем: каждый игрок, открывший вещество
    из целевого ингредиента, получает награду. День не «заканчивается за
    секунды» при 1000 игроков.

    U6/T05: флаг выполнения — completed_at, а не факт строки: раньше в
    challenge_scores писал ещё и vein-канал, и строка-«жила» ложно гасила won.
    Теперь здесь только challenge-канал; completed_at чинит и легаси-строки
    (см. миграцию в init_db). Возвращает {won, first, target_name}:
      won   — первое выполнение цели этим устройством за сегодня (выдать награду);
      first — это первое выполнение цели вообще за сегодня (для ленты).
    """
    ch = _ensure_challenge(conn)
    if not (a == ch["target"] or b == ch["target"]):
        return {"won": False, "first": False, "target_name": ch["target_name"]}
    now_iso = _now_iso()
    # I-2: единый атомарный переход вместо SELECT→UPDATE/INSERT. Прежняя
    # схема на параллельных запросах одного устройства либо давала двойной
    # won (оба потока видели completed_at IS NULL), либо роняла запрос на
    # IntegrityError отсутствующей строки. Здесь: guarded UPSERT закрывает
    # completed_at ровно один раз — rowcount==1 только у победителя перехода;
    # уже выполненная строка не матчит WHERE → rowcount==0 → просто очок.
    # Доказательство под потоками: tests/harness_atomicity_u5.py (сценарий 4).
    cur = conn.execute(
        "INSERT INTO challenge_scores (day, device_id, nick, points, first_at, completed_at) "
        "VALUES (?, ?, ?, 1, ?, ?) "
        "ON CONFLICT(day, device_id) DO UPDATE SET "
        "  points = points + 1, nick = excluded.nick, completed_at = excluded.completed_at "
        "WHERE challenge_scores.completed_at IS NULL",
        (ch["day"], device_id, nick, now_iso, now_iso),
    )
    won = cur.rowcount == 1
    if not won:
        # Цель уже выполнена этим устройством (или успела закрыться в
        # параллельном запросе секунду назад): очередной очок без награды.
        conn.execute(
            "UPDATE challenge_scores SET points = points + 1, nick = ? WHERE day = ? AND device_id = ?",
            (nick, ch["day"], device_id),
        )
        conn.commit()
        return {"won": False, "first": False, "target_name": ch["target_name"]}
    n = conn.execute(
        "SELECT COUNT(*) AS c FROM challenge_scores WHERE day = ? AND completed_at IS NOT NULL",
        (ch["day"],),
    ).fetchone()["c"]
    first = n == 1
    if first:
        conn.execute(
            "UPDATE challenges SET first_nick = ?, first_device = ? WHERE day = ?",
            (nick, device_id, ch["day"]),
        )
    conn.commit()
    return {"won": True, "first": first, "target_name": ch["target_name"]}


def _echo_row(conn: sqlite3.Connection, device_id: str):
    """Строка отголосков устройства (создаёт при отсутствии). Коммит — на вызывающем."""
    conn.execute(
        "INSERT OR IGNORE INTO echoes (device_id, balance, total) VALUES (?, 0, 0)",
        (device_id,),
    )
    return conn.execute(
        "SELECT balance, total, last_apprentice_day FROM echoes WHERE device_id = ?",
        (device_id,),
    ).fetchone()


def _credit_resonance(conn: sqlite3.Connection, out_id: int, author_nick, brewer_nick: str,
                      author_device: str = "", brewer_device: str = "",
                      pair_key: str = "") -> bool:
    """Чужой повтор вещества: +1 к счётчику вещества и отголосок
    первооткрывателю. Свои повторы и вещества без автора не засчитываются.
    Коммит — на вызывающем.

    T02: получатель ищем по device_id автора — ник — витрина, им можно
    «наследовать» чужие отголоски (смена ника/двойники). author_device пуст
    только для легаси-строк, чей автор не резолвится по нику (например, аккаунт
    удалён): для них сохранён fallback по нику, а коллизии ников устранены
    миграцией players.nick UNIQUE.

    T03 (антифарм): кредит проходит дедуп по (pair_key, brewer) — «повторил
    чужое открытие» переживается РОВНО ОДИН РАЗ НА ВСЁ ВРЕМЯ для одной пары
    одним устройством. Выбор периода — per-life, а не per-day: смысл эха —
    первое переживание чужого открытия, а per-day оставил бы вечный конвейер
    (365 эхо в год на пару с устройства) и обесценил бы вехи 10/50/100.
    Естественного суточного join-point в этом пути нет (день используется
    только «подмастерьями»). pair_key обязателен: без него
    дедуп невозможен и кредит НЕ начисляется (fail-closed — новый вызывающий
    путь не может молча обойти защиту). brewer без device_id (легаси-запросы)
    ключуется по нику с префиксом «nick:», чтобы не смешивать с устройствами.
    Атомарность: INSERT OR IGNORE по PRIMARY KEY — «check-and-mark» одним
    оператором; конкурентная гонка на одном PK пропускает ровно один кредит.
    """
    if not author_nick and not author_device:
        return False
    if author_device and brewer_device and author_device == brewer_device:
        return False  # своё вещество (даже после переименования автора)
    if not author_device and author_nick and author_nick == brewer_nick:
        return False
    if not pair_key:
        return False  # T03: дедуп обязателен — нет ключа, нет кредита
    brewer_key = brewer_device or ("nick:" + (brewer_nick or ""))
    cur = conn.execute(
        "INSERT OR IGNORE INTO resonance_seen (pair_key, brewer_key) VALUES (?, ?)",
        (pair_key, brewer_key),
    )
    if cur.rowcount == 0:
        return False  # это устройство уже «повторяло» эту пару
    conn.execute(
        "UPDATE elements SET resonance_count = resonance_count + 1 WHERE id = ?",
        (out_id,),
    )
    if author_device:
        recipients = [author_device]
    else:
        # легаси-fallback: nick после миграции UNIQUE — один владелец
        recipients = [
            prow["device_id"] for prow in conn.execute(
                "SELECT device_id FROM players WHERE nick = ?", (author_nick,)
            ).fetchall()
        ]
    credited = False
    for dev in recipients:
        _echo_row(conn, dev)
        conn.execute(
            "UPDATE echoes SET balance = MIN(balance + 1, ?), total = total + 1 "
            "WHERE device_id = ?",
            (ECHO_CAP, dev),
        )
        credited = True
    return credited


def _descendants_for(conn: sqlite3.Connection, nick: str, limit: int = 20):
    """Потомки: вещества, открытые ДРУГИМИ игроками из моих первооткрытий.
    Родословная строится по готовым a_id/b_id рецептов — новых таблиц не нужно."""
    if not nick:
        return [], 0
    ids = [
        r["id"]
        for r in conn.execute(
            "SELECT id FROM elements WHERE author = ?", (nick,)
        ).fetchall()
    ]
    if not ids:
        return [], 0
    ph = ",".join("?" for _ in ids)
    where = (
        f"(r.a_id IN ({ph}) OR r.b_id IN ({ph})) "
        "AND r.discoverer IS NOT NULL AND r.discoverer != ?"
    )
    rows = conn.execute(
        "SELECT e.name AS name, e.slug AS slug, r.discoverer AS by, "
        "r.created_at AS at FROM recipes r JOIN elements e ON e.id = r.out_id "
        f"WHERE {where} ORDER BY r.id DESC LIMIT ?",
        (*ids, *ids, nick, limit),
    ).fetchall()
    total = conn.execute(
        f"SELECT COUNT(*) AS c FROM recipes r WHERE {where}",
        (*ids, *ids, nick),
    ).fetchone()["c"]
    return [dict(r) for r in rows], total


def _apprentice_grant(conn: sqlite3.Connection, device_id: str, nick: str):
    """«Подмастерья гильдии»: раз в сутки +1 резонанс детерминированно выбранному
    своему веществу. Fallback малой аудитории — прогресс идёт и без толпы.
    Возвращает {name, slug} или None. Коммитит только при гранте."""
    if not device_id or not nick:
        return None
    row = _echo_row(conn, device_id)
    today = _today()
    if row["last_apprentice_day"] == today:
        conn.commit()
        return None
    # T02: «свои» вещества — по device_id (легаси-fallback по нику), иначе
    # переименованный игрок терял грант, а двойник ника получал чужой.
    mine = conn.execute(
        "SELECT id, name, slug FROM elements "
        "WHERE author_device = ? OR (author_device IS NULL AND author = ?) "
        "ORDER BY id",
        (device_id, nick),
    ).fetchall()
    if not mine:
        conn.commit()
        return None
    pick = mine[_hash_to_int("apprentice_" + today + "_" + device_id, len(mine))]
    conn.execute(
        "UPDATE elements SET resonance_count = resonance_count + 1 WHERE id = ?",
        (pick["id"],),
    )
    conn.execute(
        "UPDATE echoes SET balance = MIN(balance + 1, ?), total = total + 1, "
        "last_apprentice_day = ? WHERE device_id = ?",
        (ECHO_CAP, today, device_id),
    )
    conn.commit()
    return {"name": pick["name"], "slug": pick["slug"]}


def _claim_echoes(conn: sqlite3.Connection, device_id: str):
    """Списать баланс отголосков в эфир. Возвращает (claimed, ether, total).

    T29 (I-1): compare-and-swap вместо «прочитали balance → обнулили». После
    перевода HTTP-хендлеров на sync `def` (см. обоснование у get_db()) клейм
    живёт в threadpool, и два потока могли прочитать один и тот же баланс и
    выдать эфир дважды. Обнуление условно по прочитанному значению:
    rowcount == 1 — победитель, сумма ему известна (это прочитанный баланс);
    rowcount == 0 — баланс изменился между чтением и списком (параллельный
    клейм или кредит резонанса), ничего не списано, отвечаем честными нулями,
    повторный тап игрока заберёт своё. Retry-цикла намеренно нет: кредиты идут
    непрерывно и он не дал бы гарантии, а «0 сейчас» уже корректно.
    RETURNING не используется: он есть только в SQLite >= 3.35 (Debian 11 несёт
    3.34), а сервер легален на системном libsqlite3 — требование «Python >= 3.10»
    этого не покрывает. Вечный счётчик total при клейме не меняется.
    """
    row = _echo_row(conn, device_id)
    balance = row["balance"]
    cur = conn.execute(
        "UPDATE echoes SET balance = 0 WHERE device_id = ? AND balance = ?",
        (device_id, balance))
    conn.commit()
    if cur.rowcount == 1:
        return balance, balance * ECHO_ETHER, row["total"]
    loser = conn.execute(
        "SELECT total FROM echoes WHERE device_id = ?", (device_id,)
    ).fetchone()
    return 0, 0, loser["total"] if loser else 0


LETTER_BACKLOG_MAX = 7  # конвертов в запасе (недоделки старше — в архив)
LETTER_REVEAL_DAYS = 2  # через столько дней Светик называет одно вещество
ATLAS_MILE_EVERY = 10  # каждая N-я страница → +кап на клиенте
ATLAS_HISTORY_MAX = 7  # прошлых страниц в ответе (альбом)


def _date_minus(days: int) -> str:
    """Дата N дней назад в ЕДИНОЙ серверной шкале (T06): ключи писем/ревилов."""
    return (_today_date() - timedelta(days=days)).isoformat()


def _letter_candidates(conn: sqlite3.Connection, nick: str, device_id: str):
    """Пары-кандидаты в письмо: дают вещество из БД, не мои, ещё не загадывались.

    Решение пары уже зафиксировано в БД — LLM генерирует только текст намёка.
    Уровни fallback: чужие/стартовые → любые незагаданные → любые (повторы).
    """
    base_q = (
        "SELECT r.pair_key, r.a, r.b FROM recipes r "
        "JOIN elements e ON e.id = r.out_id "
    )
    not_lettered = (
        "r.pair_key NOT IN (SELECT a || '|' || b FROM letters WHERE device_id = ? "
        "UNION SELECT b || '|' || a FROM letters WHERE device_id = ?)"
    )
    # NOTE: pair_key в recipes канонический (a<b); в letters a/b тоже пишем
    # канонически, так что сравнение через NOT IN по обеим склейкам надёжно.
    tiers = [
        base_q + f"WHERE (r.discoverer IS NULL OR r.discoverer != ?) AND {not_lettered} "
        "ORDER BY r.pair_key",
        base_q + f"WHERE {not_lettered} ORDER BY r.pair_key",
        base_q + "ORDER BY r.pair_key",
    ]
    for i, q in enumerate(tiers):
        params = (nick, device_id, device_id) if i == 0 else (
            (device_id, device_id) if i == 1 else ()
        )
        rows = conn.execute(q, params).fetchall()
        if rows:
            return rows
    return []


def _ensure_letter(conn, device_id: str, nick: str, day: str, llm=None):
    """Письмо на день: вернуть строку или None (LLM недоступна / квота исчерпана — день ждёт).

    Намёк генерируется 1 раз и кэшируется; недоделки старше лимита уходят.
    Квота — отдельный дневной бюджет писем, резервируется по факту LLM-вызова
    (ключ — device_id); при отказе модели резерв возвращается.
    """
    row = conn.execute(
        "SELECT day, a, b, a_name, b_name, hint, solved FROM letters "
        "WHERE device_id = ? AND day = ?",
        (device_id, day),
    ).fetchone()
    if row:
        return row
    cands = _letter_candidates(conn, nick, device_id)
    if not cands:
        return None
    pick = cands[_hash_to_int("letter_" + day + "_" + device_id, len(cands))]
    pa, pb = sorted([pick["a"], pick["b"]])
    a_info = _parent(conn, pa)
    b_info = _parent(conn, pb)
    if llm is None:
        llm = get_llm()
    # Резерв квоты — прямо перед платным вызовом генератора намёков.
    allowed, _ = _admit_letter(conn, device_id)
    if not allowed:
        return None
    try:
        res = llm.generate_hint(a_info["name"], b_info["name"])
    except LLMError:
        _refund_letter(conn, device_id)
        return None
    hint = str(res.get("hint", "")).strip()
    if not hint:
        _refund_letter(conn, device_id)
        return None
    # Запись — атомарно (T08 по мотивам T04): под BEGIN IMMEDIATE два потока
    # на одну (device_id, day) не вставят две строки; проигравший получает
    # чужое письмо и возвращает зарезервированную квоту.
    conn.execute("BEGIN IMMEDIATE")
    try:
        cur = conn.execute(
            "INSERT OR IGNORE INTO letters (device_id, day, a, b, a_name, b_name, hint, solved) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 0)",
            (device_id, day, pa, pb, a_info["name"], b_info["name"], hint),
        )
        inserted = cur.rowcount == 1
        if inserted:
            # конвертов — не больше лимита: старые недоделки тихо уходят в архив
            conn.execute(
                "DELETE FROM letters WHERE device_id = ? AND solved = 0 AND day NOT IN "
                "(SELECT day FROM letters WHERE device_id = ? AND solved = 0 "
                "ORDER BY day DESC LIMIT ?)",
                (device_id, device_id, LETTER_BACKLOG_MAX),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    if not inserted:
        _refund_letter(conn, device_id)
    return conn.execute(
        "SELECT day, a, b, a_name, b_name, hint, solved FROM letters "
        "WHERE device_id = ? AND day = ?",
        (device_id, day),
    ).fetchone()


def _atlas_candidates(conn: sqlite3.Connection):
    """Пары в Атлас: дают вещество из БД, ещё не загадывались (фолбэк — любые).

    Атлас общемировой: персональных исключений нет, только антиповтор.
    """
    base_q = (
        "SELECT r.pair_key, r.a, r.b FROM recipes r "
        "JOIN elements e ON e.id = r.out_id "
    )
    fresh = base_q + (
        "WHERE r.pair_key NOT IN (SELECT a || '|' || b FROM atlas_pages "
        "UNION SELECT b || '|' || a FROM atlas_pages) ORDER BY r.pair_key"
    )
    rows = conn.execute(fresh).fetchall()
    if rows:
        return rows
    return conn.execute(base_q + "ORDER BY r.pair_key").fetchall()


def _ensure_atlas(conn, day: str, llm=None):
    """Страница Атласа на день: вернуть строку или None (LLM недоступна / пусто).

    Одна страница на весь мир, загадка генерируется 1 раз и кэшируется.
    Квота — отдельный дневной бюджет генераций атласа (мировой ключ),
    резервируется по факту LLM-вызова; при отказе модели или пустом
    намёке резерв возвращается, кулдаун гасит молотилку эндпоинта.
    """
    row = conn.execute(
        "SELECT day, a, b, a_name, b_name, riddle FROM atlas_pages WHERE day = ?",
        (day,),
    ).fetchone()
    if row:
        return row
    cands = _atlas_candidates(conn)
    if not cands:
        return None
    pick = cands[_hash_to_int("atlas_" + day, len(cands))]
    pa, pb = sorted([pick["a"], pick["b"]])
    a_info = _parent(conn, pa)
    b_info = _parent(conn, pb)
    if llm is None:
        llm = get_llm()
    # Резерв квоты — прямо перед платным вызовом генератора загадки.
    allowed, _ = _admit_atlas(conn)
    if not allowed:
        return None
    try:
        res = llm.generate_hint(a_info["name"], b_info["name"])
    except LLMError:
        _refund_atlas(conn)
        return None
    riddle = str(res.get("hint", "")).strip()
    if not riddle:
        _refund_atlas(conn)
        return None
    # Та же атомарность, что и для писем (T08): BEGIN IMMEDIATE + OR IGNORE;
    # проигравший гонку возвращает мировой резерв и отдаёт чужую страницу.
    conn.execute("BEGIN IMMEDIATE")
    try:
        cur = conn.execute(
            "INSERT OR IGNORE INTO atlas_pages (day, a, b, a_name, b_name, riddle) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (day, pa, pb, a_info["name"], b_info["name"], riddle),
        )
        inserted = cur.rowcount == 1
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    if not inserted:
        _refund_atlas(conn)
    return conn.execute(
        "SELECT day, a, b, a_name, b_name, riddle FROM atlas_pages WHERE day = ?",
        (day,),
    ).fetchone()


def _known_discovery(conn: sqlite3.Connection, recipe_row, pair_key: str, a: str, b: str):
    """Ответ для уже открытой пары (DiscoverResponse или None)."""
    out_row = conn.execute(
        "SELECT id, slug, name, color, layer, category, glyph, d, author, tag, created_at FROM elements WHERE id = ?",
        (recipe_row["out_id"],),
    ).fetchone()
    if not out_row:
        return None
    discoverer = recipe_row["discoverer"]
    return DiscoverResponse(
        ok=True,
        status="known",
        discovery=DiscoveryData(
            id=out_row["id"], slug=out_row["slug"], name=out_row["name"],
            color=out_row["color"], layer=out_row["layer"], category=out_row["category"],
            glyph=out_row["glyph"], d=out_row["d"],
            pair_key=pair_key, a=a, b=b, author=out_row["author"], seq=0,
            created_at=out_row["created_at"], tag=out_row["tag"],
        ),
        already_known=True,
        avatar=avatar_for(out_row["author"]) if out_row["author"] else None,
        message=(
            f"Пара {a}+{b} уже открыта {discoverer}"
            if discoverer
            else f"Пара {a}+{b} уже известна"
        ),
    )


def _existing_pair_response(conn, pair_key, a, b, nick, device_id):
    """Ответ по паре, если её судьба уже в БД (recipe/rejected) — без генерации.

    T08/U5: общий шаг для трёх точек — до лока, ПОСЛЕ захвата лока (re-check:
    воришка протухшего лока не должен второй раз платить LLM за пару, которую
    предыдущий держатель уже материализовал) и в обработчике IntegrityError.
    None — пара ещё не решена, можно генерировать.
    """
    recipe_row = conn.execute(
        "SELECT out_id, discoverer, discoverer_device FROM recipes WHERE pair_key = ?",
        (pair_key,),
    ).fetchone()
    if recipe_row:
        known = _known_discovery(conn, recipe_row, pair_key, a, b)
        if known is not None:
            _credit_resonance(conn, recipe_row["out_id"], recipe_row["discoverer"], nick,
                              author_device=recipe_row["discoverer_device"],
                              brewer_device=device_id, pair_key=pair_key)
            conn.commit()
            return known
    if conn.execute("SELECT 1 FROM rejected_pairs WHERE pair_key = ?", (pair_key,)).fetchone():
        return DiscoverResponse(
            ok=True, status="not_combinable", discovery=None, already_known=False,
            message=f"Туман рассеялся: «{a}» и «{b}» не сочетаются — элемент не создан.",
        )
    return None


def _link_existing(conn, a_slug, b_slug, a_info, b_info, pair_key, nick, row, device_id=""):
    """Привязать новую пару к уже существующему элементу (дедупликация имён).

    Новый элемент НЕ создаётся: рецепт (a,b) указывает на существующий элемент,
    игрок получает его же. DiscoveryData возвращается с reused=True — клиент
    не засчитывает это как «первооткрытие» и не создаёт дубль в своей БД.
    """
    created_at = _now_iso()
    # T28 (I-2): linked=1 — это не первооткрытие, а «дедуп имени»: строка нужна,
    # чтобы пара (a,b) была у мира, но публичные счётчики (hall-of-fame, rating)
    # такие строки считают только с AND r.linked = 0 — мутация «подставить 0/
    # убрать колонку из INSERT» красит test_linked_not_counted_in_public_counters.
    conn.execute(
        """INSERT INTO recipes (pair_key, a, b, a_id, b_id, out_id, discoverer, discoverer_device, created_at, linked)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)""",
        (pair_key, a_slug, b_slug, a_info["id"], b_info["id"], row["id"], nick, device_id, created_at),
    )
    # новая пара дала чужое вещество — автору тоже капает резонанс
    # (T03: с дедупом по pair_key — переживает только первое «повторение»)
    _credit_resonance(conn, row["id"], row["author"], nick,
                      author_device=row["author_device"] if "author_device" in row.keys() else "",
                      brewer_device=device_id, pair_key=pair_key)
    seq_row = conn.execute(
        "SELECT COUNT(*) + 1 FROM recipes WHERE created_at < ?", (created_at,)
    ).fetchone()
    return DiscoveryData(
        id=row["id"], slug=row["slug"], name=row["name"], color=row["color"],
        layer=row["layer"], category=row["category"], glyph=row["glyph"], d=row["d"],
        pair_key=pair_key, a=a_slug, b=b_slug, author=row["author"],
        avatar=avatar_for(row["author"]) if row["author"] else None,
        seq=(seq_row[0] if seq_row else 0), created_at=row["created_at"],
        gen_method="linked", reused=True, tag=row["tag"] if "tag" in row.keys() else "",
    )


def _materialize(conn, a_slug, b_slug, a_info, b_info, pair_key, nick, name, category, gen_method, glyph="", d="", tag="", device_id=""):
    """Создать элемент и рецепт; вернуть DiscoveryData.

    author/discoverer — витринный ник на момент открытия; author_device /
    discoverer_device — авторитетный ключ для экономики (T02)."""
    layer = max(a_info["layer"], b_info["layer"]) + 1
    existing_names = {row["name"] for row in conn.execute("SELECT name FROM elements").fetchall()}
    existing_slugs = {row["slug"] for row in conn.execute("SELECT slug FROM elements").fetchall()}
    existing_colors = {row["color"] for row in conn.execute("SELECT color FROM elements").fetchall()}

    slug = generate_slug(name, pair_key, existing_slugs)
    color = mix_colors(
        a_info["color"], b_info["color"],
        a_info["layer"], b_info["layer"], pair_key, existing_colors,
    )

    created_at = _now_iso()
    element_cursor = conn.execute(
        """INSERT INTO elements (slug, name, name_norm, color, layer, category, glyph, d, author, author_device, tag, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (slug, name, seed.norm_name(name), color, layer, category, glyph, d, nick, device_id, tag, created_at),
    )
    element_id = element_cursor.lastrowid
    conn.execute(
        """INSERT INTO recipes (pair_key, a, b, a_id, b_id, out_id, discoverer, discoverer_device, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (pair_key, a_slug, b_slug, a_info["id"], b_info["id"], element_id, nick, device_id, created_at),
    )
    seq_cursor = conn.execute("SELECT COUNT(*) + 1 FROM recipes WHERE created_at < ?", (created_at,))
    seq_row = seq_cursor.fetchone()
    return DiscoveryData(
        id=element_id, slug=slug, name=name, color=color, layer=layer,
        category=category, glyph=glyph, d=d, pair_key=pair_key, a=a_slug, b=b_slug,
        author=nick, avatar=avatar_for(nick), seq=(seq_row[0] if seq_row else 0),
        created_at=created_at, gen_method=gen_method, tag=tag,
    )


def _generate_for_pair(conn, a_slug, b_slug, pair_key, nick, device_id="", llm=None):
    """Решить судьбу неизвестной пары через LLM.

    БД — источник истины: вызов сюда означает, что пары нет ни в recipes, ни в
    rejected_pairs (это уже проверил вызывающий эндпоинт). Сгенерированный
    однажды результат фиксируется в БД и больше не пересчитывается.

    Квота LLM резервируется ЗДЕСЬ, по факту обращения к генератору (ключ —
    device_id). Клиентский флаг experiment на квоту не влияет (его можно
    подделать). При отказе модели («unavailable») резерв возвращается; при
    исчерпанной квоте поднимает QuotaExceeded (device_id пуст — резерв не нужен).

    Возвращает:
      ("created", DiscoveryData) — LLM дала имя, элемент создан;
      ("not_combinable", None)   — LLM сказала combinable:false (отказ фиксируется);
      ("unavailable", None)      — LLM недоступна (решение НЕ фиксируется,
                                   квота возвращена, пара остаётся кандидатом).
    """
    a_info = _parent(conn, a_slug)
    b_info = _parent(conn, b_slug)

    if llm is None:
        llm = get_llm()

    # Резерв квоты — непосредственно перед платным вызовом модели.
    reserved = False
    if device_id:
        allowed, rate_message = _admit_experiment(conn, device_id)
        if not allowed:
            raise QuotaExceeded(rate_message)
        reserved = True

    try:
        t0 = time.time()
        res = llm.generate(a_slug, b_slug, a_info["name"], b_info["name"], pair_key)
        log.info("пара %s+%s: генерация заняла %.1fs", a_slug, b_slug, time.time() - t0)
    except LLMError as e:
        # модель недоступна → не выдумываем имя и не фиксируем отказ;
        # списанную квоту возвращаем — вызова не было
        log.warning("пара %s+%s: LLM недоступна → unavailable (%s)", a_slug, b_slug, e)
        if reserved:
            _refund_experiment(conn, device_id)
        return "unavailable", None

    if res.get("combinable") is False:
        return "not_combinable", None

    name = str(res.get("name", "")).strip()
    if not name or "-" in name or "_" in name or any(ch.isdigit() for ch in name):
        # модель исчерпала попытки и не дала корректного имени → отказ
        return "not_combinable", None

    # категория — по родителям; глиф, описание и тег берём у модели (с фоллбэком)
    category = _result_category(a_info, b_info)
    glyph = str(res.get("glyph", "")).strip().lower()
    if not is_glyph(glyph):
        glyph = _fallback_glyph(name, category)
    tag = str(res.get("tag", "")).strip().lower()
    if tag not in TAGS:
        tag = category if category in TAGS else ""
    d = str(res.get("description", "")).strip().replace("\n", " ")
    d = " ".join(d.split())
    if not d or len(d) > 160 or d[:1].isdigit():
        d = "Рождено из «%s» и «%s»." % (a_info["name"], b_info["name"])

    # Дедупликация имён: если вещество с таким именем уже есть в БД (например,
    # LLM снова выдала «Огонь»), НЕ создаём копию — привязываем пару к нему.
    existing = conn.execute(
        "SELECT id, slug, name, color, layer, category, glyph, d, author, author_device, tag, created_at "
        "FROM elements WHERE name_norm = ? ORDER BY id LIMIT 1",
        (seed.norm_name(name),),
    ).fetchone()
    if existing:
        return "created", _link_existing(conn, a_slug, b_slug, a_info, b_info, pair_key, nick, existing, device_id)

    return "created", _materialize(conn, a_slug, b_slug, a_info, b_info, pair_key, nick, name, category, "llm", glyph, d, tag, device_id)


# ---------------------------------------------------------------------------
# Атомарный лок пары (T08). Раньше: SELECT-then-INSERT был неатомарен, а после
# перевода discover на sync-def (threadpool) гонка стала реальной.
# Доказательство атомарности под потоками: tests/harness_atomicity_u5.py.
# ВАЖНО: guarded UPSERT оборачивается BEGIN IMMEDIATE — вне явной транзакции
# legacy-режим sqlite3 даёт протухшие снимки, и rowcount врал при гонке
# (воспроизведено и исправлено тем же харнессом).
# ---------------------------------------------------------------------------

def _try_acquire_pair_lock(conn: sqlite3.Connection, pair_key: str, owner: str,
                           attempted_by: str, now: float) -> bool:
    """Атомарно захватить лок пары. True — захватили (строка вставлена или
    взят протухший/не-locked лок); False — живой чужой лок (state='locked',
    lock_ts свежее LOCK_TTL). Единый оператор-переход вместо check-then-act:
    два concurrent-запроса не могут оба получить True.

    U5-fix: owner — уникальный токен захвата (uuid4), а не ник: им защищено
    освобождение (см. _release_pair_lock). Ник затеявшего — attempted_by."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        cur = conn.execute(
            """INSERT INTO pending_pairs (pair_key, state, lock_ts, owner, attempted_by)
               VALUES (?, 'locked', ?, ?, ?)
               ON CONFLICT(pair_key) DO UPDATE SET
                 state='locked', lock_ts=excluded.lock_ts,
                 owner=excluded.owner, attempted_by=excluded.attempted_by
               WHERE pending_pairs.state != 'locked'
                  OR pending_pairs.lock_ts <= ?""",
            (pair_key, now, owner, attempted_by, now - LOCK_TTL),
        )
        grabbed = cur.rowcount == 1
        conn.commit()
        return grabbed
    except Exception:
        conn.rollback()
        raise


def _release_pair_lock(conn: sqlite3.Connection, pair_key: str, owner: str):
    """Снять СВОЙ лок: DELETE по токену захвата (owner). Токен надёжнее
    guard-а по lock_ts (U5-fix): два захвата в один квант time.time() на
    Windows больше не дают проигравшему «свой» lock_ts и право смахнуть
    живой чужой лок. Удаление вместо UPDATE state='resolved' (T08.2):
    отказные/прошедшие лок-строки не копятся вечно — таблица остаётся
    очередью живых блокировок."""
    conn.execute(
        "DELETE FROM pending_pairs WHERE pair_key = ? AND state = 'locked' AND owner = ?",
        (pair_key, owner),
    )
    conn.commit()


@app.post("/api/brew-check", response_model=BrewCheckResponse)
def brew_check(req: BrewCheckRequest):
    """
    Проверить, является ли пара кандидатом на первооткрытие.

    Читающий эндпоинт: авторегистрирует игрока и сообщает статус пары
    (известна / отвергнута / в обработке / кандидат). Блокировку не ставит.
    """
    conn = get_db()
    try:
        pair_key = canonical_pair_key(req.a, req.b)

        # T02: nick из запроса — только заявка новой системы; для известного
        # устройства возвращается его хранящийся ник, и дальше в ход идёт он.
        nick = _upsert_player(conn, req.nick, req.device_id)
        conn.commit()

        recipe_row = conn.execute(
            "SELECT out_id, discoverer, discoverer_device FROM recipes WHERE pair_key = ?",
            (pair_key,),
        ).fetchone()

        if recipe_row:
            # T03: brew-check — читающий путь, экономику НЕ пишет. Ранее
            # «повторил чужое открытие» засчитывался здесь на каждом чтении
            # (фарм +20 эхо → claim эфира). Осмысленное «переживание» повтора
            # — варка /api/discover (клиент реально варит пару); только её
            # known-путь и кредитует резонанс, с дедупом (pair_key, brewer)
            # раз в жизнь.
            out_row = conn.execute(
                "SELECT id, slug, name, color, layer, category, glyph, d, author, created_at FROM elements WHERE id = ?",
                (recipe_row["out_id"],),
            ).fetchone()

            discoverer = recipe_row["discoverer"]
            seq = 0
            if discoverer:
                # T28 (I-2, продолжение): ordinal «первооткрыватель №N» — тоже
                # публичный счётчик, и без linked = 0 дедуп-варки наращивали его
                # точно так же, как зал славы (тот же фарм, только показанный
                # варящему). Различник — tests/test_v31_channels.py
                # ::test_linked_not_counted_in_public_counters (brew-check).
                seq_row = conn.execute(
                    "SELECT COUNT(*) + 1 as seq FROM recipes WHERE discoverer = ? AND linked = 0 AND created_at < (SELECT created_at FROM recipes WHERE pair_key = ?)",
                    (discoverer, pair_key),
                ).fetchone()
                seq = seq_row["seq"] if seq_row and seq_row["seq"] else 0

            if out_row:
                return BrewCheckResponse(
                    ok=True,
                    pair_key=pair_key,
                    found=True,
                    status="known",
                    out={
                        "id": out_row["id"],
                        "slug": out_row["slug"],
                        "name": out_row["name"],
                        "color": out_row["color"],
                        "layer": out_row["layer"],
                        "category": out_row["category"],
                        "glyph": out_row["glyph"],
                        "d": out_row["d"],
                        "author": out_row["author"],
                        "created_at": out_row["created_at"],
                    },
                    discoverer={"nick": discoverer, "seq": seq} if discoverer else None,
                    pending=False,
                    nick=nick,
                    message=(
                        f"Рецепт {req.a}+{req.b} уже открыт {discoverer}"
                        if discoverer
                        else f"Рецепт {req.a}+{req.b} уже известен"
                    ),
                )

        # Пара признана несочетаемой?
        if conn.execute("SELECT 1 FROM rejected_pairs WHERE pair_key = ?", (pair_key,)).fetchone():
            return BrewCheckResponse(
                ok=True, pair_key=pair_key, found=False, status="not_combinable",
                out=None, discoverer=None, pending=False, nick=nick,
                message=f"«{req.a}» и «{req.b}» не сочетаются",
            )

        # Пара неизвестна — сообщить, идёт ли сейчас её обработка
        pending_row = conn.execute(
            "SELECT state, lock_ts FROM pending_pairs WHERE pair_key = ?",
            (pair_key,),
        ).fetchone()
        if pending_row and pending_row["state"] == "locked" and time.time() - pending_row["lock_ts"] < LOCK_TTL:
            return BrewCheckResponse(
                ok=True, pair_key=pair_key, found=False, status="processing",
                out=None, discoverer=None, pending=True, nick=nick,
                message="Пара в обработке — подождите",
            )

        return BrewCheckResponse(
            ok=True, pair_key=pair_key, found=False, status="candidate",
            out=None, discoverer=None, pending=False, nick=nick,
            message="Пара — кандидат на открытие",
        )

    finally:
        conn.close()

@app.post("/api/discover", response_model=DiscoverResponse)
def discover(req: DiscoverRequest):
    """
    Атомарно зарегистрировать новое первооткрытие.

    Идемпотентно: если пара уже открыта — вернуть существующий элемент;
    если признана несочетаемой — вернуть «туман» (решение фиксируется в БД).
    Новая пара: LLM-генерация. При недоступности LLM пара остаётся кандидатом
    (решение не фиксируется) — её можно сгенерировать позже.

    T04: sync `def` — генерация (requests.post до 3×30с) уходит в threadpool
    Starlette и не замораживает event loop (и /api/health вместе с ним).
    Соединение SQLite создаётся/используется/закрывается в этом же потоке.
    """
    conn = get_db()
    try:
        pair_key = canonical_pair_key(req.a, req.b)

        # T02: nick — витрина; авторитетен device_id. Дальше используется
        # канонический хранящийся ник устройства, а не переданный в запросе.
        nick = _upsert_player(conn, req.nick, req.device_id)
        conn.commit()

        # 1-2. Пара уже открыта / признана несочетаемой? (общий шаг с
        # post-lock re-check и IntegrityError-гонкой)
        existing = _existing_pair_response(conn, pair_key, req.a, req.b, nick, req.device_id)
        if existing is not None:
            return existing

        # 3. Блокировка пары — атомарный захват (T08.1): один guarded-переход
        # вместо SELECT-then-INSERT. Отказ = живой чужой лок (409, контракт не
        # менялся). owner — одноразовый токен захвата (U5-fix): освобождение
        # DELETE ... WHERE pair_key=? AND owner=? не даст проигравшему смахнуть
        # живой чужой лок (guard по lock_ts был хрупок: time.time() квантуется).
        now = time.time()
        owner = uuid.uuid4().hex
        if not _try_acquire_pair_lock(conn, pair_key, owner, nick, now):
            raise HTTPException(status_code=409, detail="Пара в обработке — повторите запрос")

        # 4. Генерация (только LLM). Кэшированные/curated пары вернулись выше —
        # до этой точки ни квоты, ни сетевого вызова нет. Квота резервируется
        # ВНУТРИ генератора по факту обращения к LLM (ключ — device_id):
        # клиентский флаг experiment её не обходит.
        try:
            # 4a. Post-lock re-check (U5-fix): между шагом 1-2 и захватом лока
            # предыдущий держатель мог истечь по TTL, быть вытесненным нами и
            # успеть материализовать/отвергнуть пару — не платим LLM второй раз
            # за то, что уже в БД.
            existing = _existing_pair_response(conn, pair_key, req.a, req.b, nick, req.device_id)
            if existing is not None:
                return existing

            # I-4 (M-4): гарантируем цель дня ДО любых записей генерации:
            # её 503 больше не приземляется в середину незакрытой транзакции
            # materialize/scoring. _ensure_challenge не читает пару и дни цели
            # не меняет — семантика скоринга та же (нужны только target/day).
            _ensure_challenge(conn)

            kind, discovery = _generate_for_pair(
                conn, req.a, req.b, pair_key, nick, req.device_id)

            if kind == "not_combinable":
                # решение модели фиксируется в БД навсегда
                conn.execute("INSERT OR IGNORE INTO rejected_pairs (pair_key) VALUES (?)", (pair_key,))
                conn.commit()
                return DiscoverResponse(
                    ok=True, status="not_combinable", discovery=None, already_known=False,
                    message=f"Туман рассеялся: «{req.a}» и «{req.b}» не сочетаются — элемент не создан.",
                )

            if kind == "unavailable":
                # LLM недоступна: решение НЕ фиксируем — пара остаётся кандидатом,
                # её можно сгенерировать позже, когда модель вернётся.
                return DiscoverResponse(
                    ok=True, status="unavailable", discovery=None, already_known=False,
                    message="Мир сейчас не может оценить эту пару — попробуйте позже.",
                )

            # U6/T05: reused (дедуп имени: пара привязана к существующему
            # веществу) — НЕ первооткрытие: linking и резонанс автору уже
            # сделал _link_existing; серверных наград нет — ни world_event,
            # ни challenge/vein-очков, ни звания «ПЕРВООТКРЫТИЕ». Иначе
            # многопарный фарш на одно имя фармит дневные очки и спамит ленту.
            if discovery.reused:
                conn.commit()
                return DiscoverResponse(
                    ok=True, status="created", discovery=discovery, already_known=False,
                    message=f"Пара {req.a}+{req.b} уже ведёт к веществу «{discovery.name}».",
                )

            # лента событий мира
            conn.execute(
                "INSERT INTO world_events (pair_key, a, b, out, out_name, discoverer, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (pair_key, req.a, req.b, discovery.slug, discovery.name, nick,
                 _now_iso()),
            )
            # ежедневная личная цель дня
            challenge_info = _score_challenge(conn, req.a, req.b, nick, req.device_id)
            # туманная жила: находка с тегом цикла → +очки и бросок прожилки
            # (T6: цикл-скорер вместо недельного; reused-ветка наград не даёт)
            cycle = _ensure_active_cycle(conn)
            vein_info = _score_vein_cycle(
                conn, cycle, discovery.tag or "", pair_key,
                req.device_id, nick, is_world_first=True,
            )
            # порог/возраст цикла → активный цикл переходит в spread
            _maybe_spread_cycle(conn, cycle)
            conn.commit()
            return DiscoverResponse(
                ok=True, status="created", discovery=discovery, already_known=False,
                message=f"ПЕРВООТКРЫТИЕ: {discovery.name} автор — {nick}!",
                challenge=challenge_info,
                vein=vein_info,
            )

        except QuotaExceeded as e:
            # квота исчерпана до обращения к LLM: лок снимаем в finally,
            # пара останется кандидатом на будущие дни
            return DiscoverResponse(
                ok=False, status="rate_limited", discovery=None, already_known=False,
                message=e.text,
            )

        except sqlite3.IntegrityError:
            conn.rollback()
            # гонка: пара вставлена другим запросом — отдать существующую
            # (тот же общий шаг; не_combinable-гонка тоже разрешается корректно)
            existing = _existing_pair_response(conn, pair_key, req.a, req.b, nick, req.device_id)
            if existing is not None:
                return existing
            raise

        except Exception:
            # I-4: нештатная ошибка (SQLITE_BUSY вне логики лока, 503, баг
            # генератора) — бизнес-записи этой транзакции (elements/recipes/
            # world_events/скоринг) НЕ должны быть частично закоммичены:
            # иначе элемент создан, а награда/цель не досчитались — навсегда.
            # Откатываем до освобождения лока, чтобы release шёл по чистому
            # соединению и его commit покрывал только DELETE.
            conn.rollback()
            raise

        finally:
            # Сброс блокировки: удаление СВОЕГО лока по токену захвата (owner)
            # — проигравший гонку перезахвата не смахнёт живой чужой лок
            # (U5-fix; раньше guard был по lock_ts и ломался на квантах
            # time.time()). Могилы state='resolved' не копятся (T08.2).
            _release_pair_lock(conn, pair_key, owner)

    finally:
        conn.close()

@app.post("/api/vein/find", response_model=VeinFindResponse)
def vein_find(req: VeinFindRequest):
    """Register a personal find: pair exists in server recipes but not in
    personal_discoveries for this device. Scores +1 point, 10% streak roll.

    T04/T29 форма: sync def (threadpool), commit в конце успешного пути,
    rollback по исключению, close в finally (как /api/discover).
    """
    conn = get_db()
    try:
        # Личное нахождение не несёт игрового ника: для известного устройства
        # _upsert_player возвращает хранящийся ник (переданный игнорируется),
        # новое устройство заводится с дефолтом клиента («Алхимик», унификация
        # при коллизии — внутри _upsert_player). Пустая строка тут недопустима:
        # clean_nick("") упал бы в 400 на первом же запросе нового устройства.
        nick = _upsert_player(conn, "Алхимик", req.device_id)
        conn.commit()

        # Validate cycle_id matches current active/spread
        cycle = _ensure_active_cycle(conn)
        if req.cycle_id != cycle["cycle_id"]:
            # Check if it matches a spread cycle still active
            spread_row = conn.execute(
                "SELECT * FROM vein_cycles WHERE cycle_id=? AND state='spread'",
                (req.cycle_id,),
            ).fetchone()
            if spread_row:
                cycle = dict(spread_row)
            else:
                return VeinFindResponse(ok=False, error="cycle_mismatch", cycle_id=cycle["cycle_id"])

        # Pair must be known to the server (recipe + its output element)
        recipe = conn.execute(
            "SELECT out_id FROM recipes WHERE pair_key=?", (req.pair_key,)
        ).fetchone()
        if not recipe:
            return VeinFindResponse(ok=False, error="unknown_pair")
        elem = conn.execute(
            "SELECT tag FROM elements WHERE id=?", (recipe["out_id"],)
        ).fetchone()
        if not elem:
            return VeinFindResponse(ok=False, error="unknown_element")
        if elem["tag"] != req.tag:
            return VeinFindResponse(ok=False, error="tag_mismatch")

        # Check tag is active in cycle
        active_tags = {cycle["tag1"]}
        if cycle["tag2"]:
            active_tags.add(cycle["tag2"])
        if req.tag not in active_tags:
            return VeinFindResponse(ok=False, error="tag_mismatch")

        # Idempotency: already scored this (device, cycle, pair)?
        existing_hit = conn.execute(
            "SELECT 1 FROM vein_hits WHERE device_id=? AND cycle_id=? AND pair_key=?",
            (req.device_id, cycle["cycle_id"], req.pair_key),
        ).fetchone()
        if existing_hit:
            # Return original result from vein_streaks
            streak_row = conn.execute(
                "SELECT count, cap_claimed FROM vein_streaks WHERE device_id=? AND cycle_id=?",
                (req.device_id, cycle["cycle_id"]),
            ).fetchone()
            return VeinFindResponse(
                ok=True, points=1,
                streak_added=False,
                streak_count=streak_row["count"] if streak_row else 0,
                cap_reached=bool(streak_row["cap_claimed"]) if streak_row else False,
                cycle_id=cycle["cycle_id"],
            )

        # Check if this personal discovery already exists (anti-farm: one per device globally)
        existing_discovery = conn.execute(
            "SELECT 1 FROM personal_discoveries WHERE device_id=? AND pair_key=?",
            (req.device_id, req.pair_key),
        ).fetchone()
        if existing_discovery:
            # Already claimed this pair as personal find in some previous cycle
            # Return success but don't score again
            streak_row = conn.execute(
                "SELECT count, cap_claimed FROM vein_streaks WHERE device_id=? AND cycle_id=?",
                (req.device_id, cycle["cycle_id"]),
            ).fetchone()
            return VeinFindResponse(
                ok=True, points=0,
                streak_added=False,
                streak_count=streak_row["count"] if streak_row else 0,
                cap_reached=bool(streak_row["cap_claimed"]) if streak_row else False,
                cycle_id=cycle["cycle_id"],
            )

        # Register personal discovery (PK device_id+pair_key — глобальный:
        # один раз на устройство, не повторяется в новых циклах)
        conn.execute(
            "INSERT INTO personal_discoveries (device_id, pair_key, discovered_at) "
            "VALUES (?, ?, ?)",
            (req.device_id, req.pair_key, _now_iso()),
        )

        # Score
        result = _score_vein_cycle(
            conn, cycle, req.tag, req.pair_key,
            req.device_id, nick, is_world_first=False,
        )
        if result is None:
            conn.rollback()
            return VeinFindResponse(ok=False, error="scoring_failed")

        # Check cycle spread transition (state у dict-а после CAS-loss не
        # перечитывается — endpoint дальше cycle не использует)
        _maybe_spread_cycle(conn, cycle)

        conn.commit()
        return VeinFindResponse(
            ok=True,
            points=result["points"],
            streak_added=result["streak_added"],
            streak_count=result["streak_count"],
            cap_reached=result["cap_reached"],
            cycle_id=cycle["cycle_id"],
        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

@app.post("/api/vein/pour", response_model=VeinPourResponse)
def vein_pour(req: VeinPourRequest):
    """UI-only ceremony. Records pour in vein_pour_log for idempotency.
    Never scores points."""
    conn = get_db()
    try:
        existing = conn.execute(
            "SELECT 1 FROM vein_pour_log WHERE device_id=? AND idempotency_key=?",
            (req.device_id, req.idempotency_key),
        ).fetchone()
        if existing:
            return VeinPourResponse(ok=True, already_poured=True)
        conn.execute(
            "INSERT INTO vein_pour_log (device_id, idempotency_key, processed_at) VALUES (?, ?, ?)",
            (req.device_id, req.idempotency_key, _now_iso()),
        )
        conn.commit()
        return VeinPourResponse(ok=True, already_poured=False)
    except sqlite3.IntegrityError:
        # Race: another request inserted same key
        return VeinPourResponse(ok=True, already_poured=True)
    finally:
        conn.close()

@app.get("/api/vein/cycle/status", response_model=CycleStatusResponse)
def vein_cycle_status(device_id: str = Query("", max_length=128)):
    """Cycle status for vein. Independent from /api/week/status (Fair).

    Lazy-creates the current cycle and drives the spread->closed expiry
    (VEIN_SPREAD_DURATION days after spread_at), then returns the FRESH
    active cycle. Sync `def` (T29): threadpool, close in finally; коммит
    только там, где _ensure_active_cycle что-то вставил (read-only путь
    остаётся без записи).
    """
    conn = get_db()

    def _ensure_committed() -> dict:
        # _ensure_active_cycle INSERT не коммитит (коммит на вызывающем):
        # детектируем факт создания, чтобы повторные GET отдавали тот же
        # цикл, а не пересоздавали его на каждом запросе.
        had_cycle = conn.execute(
            "SELECT 1 FROM vein_cycles WHERE state IN ('active', 'spread') LIMIT 1"
        ).fetchone() is not None
        c = _ensure_active_cycle(conn)
        if not had_cycle:
            conn.commit()
        return c

    try:
        cycle = _ensure_committed()
        # Expiry: только spread с выставленным spread_at.
        if cycle["state"] == "spread" and cycle["spread_at"]:
            spread_date = date.fromisoformat(cycle["spread_at"][:10])
            if (_today_date() - spread_date).days >= VEIN_SPREAD_DURATION:
                cursor = conn.execute(
                    "UPDATE vein_cycles SET state='closed', ended_at=? "
                    "WHERE cycle_id=? AND state='spread'",
                    (_now_iso(), cycle["cycle_id"]),
                )
                if cursor.rowcount == 1:
                    # CAS выигран: закрытие + создание свежего цикла — в один
                    # коммит (cycle_id с uuid-суффиксом не коллизируют в секунду
                    # закрытия).
                    cycle = _ensure_active_cycle(conn)
                    conn.commit()
                else:
                    # CAS проигран: ряд уже перевёл другой запрос — перечитываем.
                    row = conn.execute(
                        "SELECT * FROM vein_cycles WHERE cycle_id=?",
                        (cycle["cycle_id"],),
                    ).fetchone()
                    cycle = dict(row)
                    if cycle["state"] not in ("active", "spread"):
                        cycle = _ensure_committed()

        my_points = 0
        my_streak = 0
        if device_id:
            # Сумма очков по всем дням этого цикла (vein_points.day >= дата старта).
            pts_row = conn.execute(
                "SELECT COALESCE(SUM(points), 0) AS total FROM vein_points "
                "WHERE device_id=? AND day >= date(?)",
                (device_id, cycle["started_at"][:10]),
            ).fetchone()
            my_points = pts_row["total"] if pts_row else 0
            streak_row = conn.execute(
                "SELECT count FROM vein_streaks WHERE device_id=? AND cycle_id=?",
                (device_id, cycle["cycle_id"]),
            ).fetchone()
            my_streak = streak_row["count"] if streak_row else 0

        return CycleStatusResponse(
            ok=True,
            cycle_id=cycle["cycle_id"],
            tag1=cycle["tag1"],
            tag2=cycle["tag2"],
            state=cycle["state"],
            world_finds=cycle["world_finds"],
            my_points=my_points,
            my_streak=my_streak,
            started_at=cycle["started_at"],
            spread_threshold=int(cycle["spread_threshold"]),
        )
    finally:
        conn.close()

@app.get("/api/world", response_model=WorldResponse)
def world(
    page: int = Query(1, ge=1, description="Номер страницы"),
    per_page: int = Query(50, ge=1, le=100, description="Количество на странице"),
):
    """
    Получить список всех известных элементов с пагинацией.
    """
    conn = get_db()
    try:
        total_cursor = conn.execute("SELECT COUNT(*) as total FROM elements")
        total_row = total_cursor.fetchone()
        total = total_row["total"]
        
        offset = (page - 1) * per_page
        
        elements_cursor = conn.execute(
            "SELECT id, slug, name, color, layer, category, glyph, d, author, created_at FROM elements ORDER BY id LIMIT ? OFFSET ?",
            (per_page, offset),
        )
        rows = elements_cursor.fetchall()
        
        elements = [
            ElementData(
                id=r["id"],
                slug=r["slug"],
                name=r["name"],
                color=r["color"],
                layer=r["layer"],
                category=r["category"],
                glyph=r["glyph"],
                d=r["d"],
                author=r["author"],
                avatar=avatar_for(r["author"]) if r["author"] else None,
                created_at=r["created_at"],
            )
            for r in rows
        ]
        
        return WorldResponse(
            ok=True,
            elements=elements,
            page=page,
            per_page=per_page,
            total=total,
        )
        
    finally:
        conn.close()

@app.get("/api/hall-of-fame", response_model=HallResponse)
def hall_of_fame():
    """
    Топ-10 игроков по количеству первооткрытий.
    """
    conn = get_db()
    try:
        # T28 (I-2): r.linked = 0 — «дедуп-имена» (_link_existing) славу не
        # двигают; кейс-мутант — tests/test_v31_channels.py
        # ::test_linked_not_counted_in_public_counters.
        hall_cursor = conn.execute(
            """SELECT 
                p.nick,
                COUNT(r.id) as count,
                MAX(r.created_at) as updated_at
            FROM recipes r
            JOIN players p ON r.discoverer = p.nick
            WHERE p.device_id NOT LIKE 'bot-%' AND r.linked = 0
            GROUP BY p.nick
            ORDER BY count DESC, updated_at DESC
            LIMIT 10""",
        )
        rows = hall_cursor.fetchall()
        
        hall = [
            HallEntry(
                rank=i + 1,
                nick=r["nick"],
                avatar=avatar_for(r["nick"]),
                count=r["count"],
                updated_at=r["updated_at"],
            )
            for i, r in enumerate(rows)
        ]
        
        return HallResponse(ok=True, hall=hall)
        
    finally:
        conn.close()

@app.get("/api/events", response_model=EventsResponse)
def events(limit: int = Query(20, ge=1, le=100)):
    """Лента последних первооткрытий мира (для «живой ленты» в игре)."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT e.*, ea.name AS a_name, eb.name AS b_name "
            "FROM world_events e "
            "LEFT JOIN elements ea ON ea.slug = e.a "
            "LEFT JOIN elements eb ON eb.slug = e.b "
            "ORDER BY e.id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        now_dt = _now_dt()
        evs = []
        for r in rows:
            ago = 0
            try:
                # T06: created_at пишется в единой шкале (_now_iso) — разница
                # тоже в единой шкале, без .timestamp() (тот трактовал naive
                # как LOCAL-время хоста и врал на не-UTC сервере).
                ago = max(0, int((now_dt - datetime.fromisoformat(r["created_at"])).total_seconds()))
            except (ValueError, TypeError):
                ago = 0
            evs.append({
                "pair_key": r["pair_key"], "a": r["a"], "b": r["b"],
                "a_name": r["a_name"] or "", "b_name": r["b_name"] or "",
                "out": r["out"], "out_name": r["out_name"],
                "discoverer": r["discoverer"],
                "avatar": avatar_for(r["discoverer"]) if r["discoverer"] else None,
                "created_at": r["created_at"],
                "ago_sec": ago,
            })
        return EventsResponse(ok=True, events=evs)
    finally:
        conn.close()


@app.get("/api/challenge", response_model=ChallengeResponse)
def challenge(device_id: str = Query("", max_length=128)):
    """Ежедневная цель: целевой ингредиент, первый справившийся, счётчик дня.

    U6/T05: completions — только реальные выполнения цели (challenge_scores,
    completed_at); vein-строки больше не попадают в таблицу, а легаси-строки
    без completed_at не считаются. my_points — сумма обоих каналов
    (challenge + жила): игрок видит честно заработанные им очки дня."""
    conn = get_db()
    try:
        ch = _ensure_challenge(conn)
        # T06: «сегодня» для ленты — Python-ключ дня единой шкалы (UTC+смещение),
        # а не SQLite date('now') (чистый UTC): goal дня и today_events теперь
        # переворачиваются в ОДИН момент.
        today_count = conn.execute(
            "SELECT COUNT(*) AS c FROM world_events WHERE date(created_at) = ?",
            (_today(),),
        ).fetchone()["c"]
        first = ch["first_nick"]
        completions = conn.execute(
            "SELECT COUNT(*) AS c FROM challenge_scores "
            "WHERE day = ? AND completed_at IS NOT NULL",
            (ch["day"],),
        ).fetchone()["c"]
        my_points = 0
        my_points_total = 0
        if device_id:
            def _chan_points(table):
                d = conn.execute(
                    f"SELECT points FROM {table} WHERE day = ? AND device_id = ?",
                    (ch["day"], device_id),
                ).fetchone()
                t = conn.execute(
                    f"SELECT COALESCE(SUM(points), 0) AS s FROM {table} WHERE device_id = ?",
                    (device_id,),
                ).fetchone()
                return (d["points"] if d else 0), (t["s"] if t else 0)
            ch_day, ch_total = _chan_points("challenge_scores")
            vn_day, vn_total = _chan_points("vein_points")
            my_points = ch_day + vn_day
            my_points_total = ch_total + vn_total
        return ChallengeResponse(
            ok=True, day=ch["day"], target=ch["target"],
            target_name=ch["target_name"], hint=ch["hint"],
            first_nick=first,
            first_avatar=avatar_for(first) if first else None,
            completions=completions,
            my_points=my_points,
            my_points_total=my_points_total,
            today_events=today_count,
        )
    finally:
        conn.close()


@app.post("/api/player/register")
def register_player(req: BrewCheckRequest):
    """
    Регистрация игрока (device_id должен быть уникальным).

    T02: повторная «регистрация» чужим ником не переименовывает существующий
    аккаунт — ник меняется только через POST /api/me.
    """
    conn = get_db()
    try:
        nick = _upsert_player(conn, req.nick, req.device_id)
        conn.commit()
        return {"ok": True, "nick": nick, "device_id": req.device_id}
    finally:
        conn.close()


@app.get("/api/me", response_model=ProfileResponse)
def get_me(device_id: str = Query(..., min_length=1, max_length=128),
           limit_guests: int = Query(8, ge=0, le=20)):
    """Профиль игрока: ник и процедурный аватар по device_id."""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT nick FROM players WHERE device_id = ?", (device_id,)
        ).fetchone()
        nick = row["nick"] if row else ""
        return ProfileResponse(
            ok=True, nick=nick, device_id=device_id, avatar=avatar_for(nick or device_id),
            house_visits_week=_visits_week(conn, device_id),
            house_visitors=_guest_list(conn, device_id, limit_guests),
        )
    finally:
        conn.close()


@app.post("/api/me", response_model=ProfileResponse)
def set_me(req: ProfileRequest):
    """Установить ник игрока (уникальное имя); аватар считается из ника.

    Единственная дверь переименования (T02): ник занят другим устройством —
    400. Легаси-авторство со старым ником перепривязывается на device_id
    владельца, чтобы угон освободившегося ника не унаследовал отголоски.
    """
    nick = clean_nick(req.nick)
    if not nick:
        raise HTTPException(status_code=400, detail="Ник должен быть 2–24 символа и без спецсимволов")
    conn = get_db()
    try:
        taken = conn.execute(
            "SELECT device_id FROM players WHERE nick = ? AND device_id <> ?",
            (nick, req.device_id),
        ).fetchone()
        if taken:
            raise HTTPException(status_code=400, detail="Ник уже занят")
        old = conn.execute(
            "SELECT nick FROM players WHERE device_id = ?", (req.device_id,)
        ).fetchone()
        try:
            conn.execute(
                """INSERT INTO players (nick, device_id, created_at) VALUES (?, ?, ?)
                   ON CONFLICT(device_id) DO UPDATE SET nick = excluded.nick""",
                (nick, req.device_id, _now_iso()),
            )
        except sqlite3.IntegrityError:
            # гонка: ник заняли между проверкой и записью
            raise HTTPException(status_code=400, detail="Ник уже занят")
        if old and old["nick"] and old["nick"] != nick:
            # перепривязка легаси-авторства (author_device ещё не заполнен)
            conn.execute(
                "UPDATE elements SET author_device = ? "
                "WHERE author_device IS NULL AND author = ?",
                (req.device_id, old["nick"]),
            )
            conn.execute(
                "UPDATE recipes SET discoverer_device = ? "
                "WHERE discoverer_device IS NULL AND discoverer = ?",
                (req.device_id, old["nick"]),
            )
        conn.commit()
        # γ: переименование отдаёт те же дом-поля, что и GET /api/me, — иначе
        # ответ POST /api/me с дефолтами 0/[] сбрасывает ленту гостей клиента
        # до следующего GET-синка. 8 — дефолт limit_guests из GET /api/me
        # (POST параметров запроса не несёт).
        return ProfileResponse(
            ok=True, nick=nick, device_id=req.device_id, avatar=avatar_for(nick),
            house_visits_week=_visits_week(conn, req.device_id),
            house_visitors=_guest_list(conn, req.device_id, 8),
        )
    finally:
        conn.close()


@app.get("/api/account/export")
def export_account(device_id: str = Query(..., min_length=1, max_length=128)):
    """Экспорт серверных данных игрока перед удалением аккаунта.

    Игровой мир публичен, но персональная связь с ним возвращается в экспорте
    и удаляется/анонимизируется отдельным DELETE-запросом.
    """
    conn = get_db()
    try:
        player = conn.execute(
            "SELECT nick, house, created_at, last_seen FROM players WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if player is None:
            return {"ok": True, "found": False, "device_id": device_id, "data": {}}
        nick = player["nick"]
        # T02: авторство — по device_id; легаси-строки без author_device
        # сопоставляются по нику (ник после миграции уникален).
        discoveries = [dict(row) for row in conn.execute(
            """SELECT slug, name, layer, category, created_at
               FROM elements
               WHERE author_device = ?
                  OR (author_device IS NULL AND author = ?)
               ORDER BY created_at""", (device_id, nick)
        ).fetchall()]
        echoes_row = conn.execute(
            "SELECT balance, total FROM echoes WHERE device_id = ?", (device_id,)
        ).fetchone()
        house = None
        if player["house"]:
            try:
                house = json.loads(player["house"])
            except (TypeError, json.JSONDecodeError):
                house = None
        return {
            "ok": True,
            "found": True,
            "device_id": device_id,
            "data": {
                "profile": {
                    "nick": nick,
                    "created_at": player["created_at"],
                    "last_seen": player["last_seen"],
                },
                "house": house,
                "discoveries": discoveries,
                "echoes": dict(echoes_row) if echoes_row else {"balance": 0, "total": 0},
            },
        }
    finally:
        conn.close()


@app.delete("/api/account")
def delete_account(device_id: str = Query(..., min_length=1, max_length=128)):
    """Удалить профиль и персональные связи, сохранив общий мир.

    Вещества, уже опубликованные в мир, не удаляются: иначе удаление одного
    игрока ломало бы рецепты остальных. Поля авторства и публичная лента
    заменяются на «Анонимный алхимик».
    """
    conn = get_db()
    try:
        player = conn.execute("SELECT nick FROM players WHERE device_id = ?", (device_id,)).fetchone()
        if player is None:
            return {"ok": True, "deleted": False, "message": "Профиль уже удалён"}
        nick = player["nick"]
        # T02: чистим авторство СВОЕГО устройства и легаси-строк, чей ник ещё
        # не привязан к device. Раньше WHERE nick задевал всех
        # однофамильцев — это был и угон, и порча чужих аккаунтов.
        conn.execute(
            "UPDATE elements SET author = NULL, author_device = NULL "
            "WHERE author_device = ? OR (author_device IS NULL AND author = ?)",
            (device_id, nick),
        )
        conn.execute(
            "UPDATE recipes SET discoverer = NULL, discoverer_device = NULL "
            "WHERE discoverer_device = ? OR (discoverer_device IS NULL AND discoverer = ?)",
            (device_id, nick),
        )
        conn.execute(
            "UPDATE world_events SET discoverer = 'Анонимный алхимик' WHERE discoverer = ?", (nick,)
        )
        conn.execute(
            "UPDATE challenges SET first_nick = 'Анонимный алхимик', first_device = NULL WHERE first_device = ?",
            (device_id,),
        )
        for table in [
            "echoes", "letters", "challenge_scores", "vein_points", "atlas_solves",
            "fair_pairs", "fair_contrib", "fair_claims", "vein_hits", "legacy_vein_hits",
            # F3 (приватность): цикл-модель жилы добавила свои таблицы —
            # личные находки, прожилки и журнал вливаний тоже чистим.
            "personal_discoveries", "vein_streaks", "vein_pour_log",
        ]:
            conn.execute(f"DELETE FROM {table} WHERE device_id = ?", (device_id,))
        conn.execute("DELETE FROM players WHERE device_id = ?", (device_id,))
        conn.commit()
        return {"ok": True, "deleted": True, "device_id": device_id}
    finally:
        conn.close()


@app.get("/api/rejected", response_model=RejectedResponse)
def rejected(limit: int = Query(5000, ge=1, le=200000)):
    """Пары, которые сервер уже признал несочетаемыми (для фильтрации намёков)."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT pair_key FROM rejected_pairs ORDER BY rowid DESC LIMIT ?", (limit,)
        ).fetchall()
        return RejectedResponse(ok=True, rejected=[r["pair_key"] for r in rows])
    finally:
        conn.close()


def _visits_week(conn: sqlite3.Connection, host_device: str) -> int:
    """γ: уникальных гостей хоста за последние VISITS_WEEK_DAYS дней (включая сегодня)."""
    since = _date_minus(VISITS_WEEK_DAYS - 1)
    return conn.execute(
        "SELECT COUNT(DISTINCT visitor_device) AS c FROM house_visits "
        "WHERE host_device = ? AND day >= ?",
        (host_device, since),
    ).fetchone()["c"]


def _guest_list(conn: sqlite3.Connection, host_device: str, limit: int = 10) -> list[HouseGuest]:
    """γ §7.2: последние гости хоста (ник + аватар + день визита).

    INNER JOIN по players: гость, который ни разу не регистрировался (нет
    строки в players), в ленту не попадает — показывать внутренний device_id
    вместо имени нечего, а такой визит всё равно засчитан в visits_week.
    Порядок day DESC, затем visitor_device: в house_visits нет INTEGER
    PRIMARY KEY (составной текстовый PK → rowid отсутствует), поэтому второго
    ключа сортировки, кроме самих колонок PK, у записей просто нет.
    """
    since = _date_minus(VISITS_WEEK_DAYS - 1)
    rows = conn.execute(
        "SELECT hv.day AS day, p.nick AS nick FROM house_visits hv "
        "JOIN players p ON p.device_id = hv.visitor_device "
        "WHERE hv.host_device = ? AND hv.day >= ? "
        "ORDER BY hv.day DESC, hv.visitor_device ASC LIMIT ?",
        (host_device, since, limit),
    ).fetchall()
    return [HouseGuest(nick=r["nick"], avatar=avatar_for(r["nick"]), day=r["day"]) for r in rows]


@app.post("/api/house", response_model=HouseResponse)
def save_house(req: HouseRequest):
    """Сохранить домик игрока, чтобы его могли открывать другие игроки."""
    conn = get_db()
    try:
        # T02: ник из запроса ничего не переименовывает — канонический ник
        # возвращает _upsert_player (для знакомого устройства — хранящийся).
        nick = _upsert_player(conn, req.nick, req.device_id)
        house_json = json.dumps(req.house, ensure_ascii=False)
        if len(house_json) > 16384:
            raise HTTPException(status_code=400, detail="Домик слишком большой")
        conn.execute(
            "UPDATE players SET house = ?, house_updated_at = ? WHERE device_id = ?",
            (house_json, _now_iso(), req.device_id),
        )
        conn.commit()
        return HouseResponse(ok=True, nick=nick, avatar=avatar_for(nick), house=req.house)
    finally:
        conn.close()


VISITS_PER_VISITOR_DAY = 10   # γ: анти-фарм — разных хостов на посетителя в день
VISITS_WEEK_DAYS = 7          # окно «недели гостей» = 7 дней по единой шкале (T06)


@app.post("/api/house/visit", response_model=HouseVisitResponse)
def visit_house(req: HouseVisitRequest):
    """Засвидетельствовать визит в чужой домик.

    Награда хоста — на клиенте (спека §7.3): здесь только источник истины числа
    и суточный анти-фарм. Визит (host, visitor, day) идемпотентен.
    """
    conn = get_db()
    try:
        host = conn.execute(
            "SELECT device_id, house FROM players WHERE nick = ? ORDER BY id DESC LIMIT 1",
            (req.host_nick,),
        ).fetchone()
        # сначала «сам себе»: у игрока без домика свой ник тоже находится по nick
        if host and host["device_id"] == req.device_id:
            raise HTTPException(status_code=400, detail="Себя не навестишь")
        if not host or not host["house"]:
            return HouseVisitResponse(ok=False, found=False, visits_week=0)
        day = _today()
        known = conn.execute(
            "SELECT 1 FROM house_visits WHERE host_device = ? AND visitor_device = ? AND day = ?",
            (host["device_id"], req.device_id, day),
        ).fetchone()
        if known is None:
            used = conn.execute(
                "SELECT COUNT(DISTINCT host_device) AS c FROM house_visits "
                "WHERE visitor_device = ? AND day = ?",
                (req.device_id, day),
            ).fetchone()["c"]
            if used >= VISITS_PER_VISITOR_DAY:
                raise HTTPException(
                    status_code=429,
                    detail="Лимит %d визитов в день исчерпан" % VISITS_PER_VISITOR_DAY,
                )
        # сравнение выше и вставка — не один транзакционный шаг: при гонке двух
        # параллельных визитов лимит может «протечь» на +1. Это анти-фарм, а не
        # экономика, и документировано здесь, а не чинится мьютексом.
        conn.execute(
            "INSERT OR IGNORE INTO house_visits (host_device, visitor_device, day) VALUES (?, ?, ?)",
            (host["device_id"], req.device_id, day),
        )
        conn.commit()
        return HouseVisitResponse(
            ok=True, found=True, visits_week=_visits_week(conn, host["device_id"]))
    finally:
        conn.close()


@app.get("/api/house", response_model=HouseResponse)
def get_house(nick: str = Query(..., min_length=1, max_length=64)):
    """Домик игрока по нику (публичный; None, если не построен)."""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT nick, device_id, house FROM players WHERE nick = ? ORDER BY id DESC LIMIT 1", (nick,)
        ).fetchone()
        if not row:
            return HouseResponse(ok=True, nick=nick, avatar=avatar_for(nick), house=None, found=False)
        house = None
        if row["house"]:
            try:
                house = json.loads(row["house"])
            except ValueError:
                house = None
        return HouseResponse(
            ok=True, nick=row["nick"], avatar=avatar_for(row["nick"]), house=house,
            visits_week=_visits_week(conn, row["device_id"]),
        )
    finally:
        conn.close()


@app.get("/api/rating", response_model=RatingResponse)
def rating(device_id: str = Query("", max_length=128)):
    """Рейтинг игроков: открытия, вещества, очки целей, наличие домика."""
    conn = get_db()
    try:
        # T28 (I-2): discoveries — только настоящие первооткрытия (r.linked = 0),
        # linked-строки дедупа имени здесь не считаются (см. _link_existing).
        since = _date_minus(VISITS_WEEK_DAYS - 1)
        rows = conn.execute(
            """SELECT p.nick, p.house, p.created_at,
                   (SELECT COUNT(DISTINCT hv.visitor_device) FROM house_visits hv
                      WHERE hv.host_device = p.device_id AND hv.day >= ?) AS house_guests,
                   (SELECT COUNT(*) FROM recipes r WHERE r.discoverer = p.nick AND r.linked = 0) AS discoveries,
                   (SELECT COUNT(*) FROM elements e WHERE e.author = p.nick) AS elements,
                   (SELECT COALESCE(SUM(c.points), 0) FROM challenge_scores c WHERE c.nick = p.nick)
                 + (SELECT COALESCE(SUM(v.points), 0) FROM vein_points v WHERE v.nick = p.nick) AS points
            FROM players p
            ORDER BY discoveries DESC, elements DESC, points DESC, p.created_at ASC""",
            (since,),
        ).fetchall()
        built = [
            RatingRow(
                rank=i + 1, nick=r["nick"], avatar=avatar_for(r["nick"]),
                discoveries=r["discoveries"], elements=r["elements"],
                points=r["points"], house_built=bool(r["house"]),
                house_guests=r["house_guests"],
                updated_at=r["created_at"],
            )
            for i, r in enumerate(rows)
        ]
        me = None
        if device_id:
            mrow = conn.execute("SELECT nick FROM players WHERE device_id = ?", (device_id,)).fetchone()
            if mrow:
                me = next((x for x in built if x.nick == mrow["nick"]), None)
        return RatingResponse(ok=True, rows=built[:50], me=me)
    finally:
        conn.close()


@app.get("/api/echoes", response_model=EchoesResponse)
def echoes(device_id: str = Query("", max_length=128)):
    """Резонанс 2.0: баланс отголосков, вечный счётчик, топ веществ и потомки."""
    conn = get_db()
    try:
        nick = ""
        if device_id:
            prow = conn.execute(
                "SELECT nick FROM players WHERE device_id = ?", (device_id,)
            ).fetchone()
            if prow and prow["nick"]:
                nick = prow["nick"]
        apprentice = _apprentice_grant(conn, device_id, nick) if device_id else None
        balance, total = 0, 0
        if device_id:
            erow = conn.execute(
                "SELECT balance, total FROM echoes WHERE device_id = ?",
                (device_id,),
            ).fetchone()
            if erow:
                balance, total = erow["balance"], erow["total"]
        top = []
        if nick:
            for t in conn.execute(
                "SELECT name, slug, resonance_count FROM elements "
                "WHERE author = ? AND resonance_count > 0 "
                "ORDER BY resonance_count DESC, id ASC LIMIT 5",
                (nick,),
            ).fetchall():
                top.append(EchoTop(name=t["name"], slug=t["slug"], count=t["resonance_count"]))
        desc, desc_total = _descendants_for(conn, nick)
        return EchoesResponse(
            ok=True, nick=nick, balance=balance, total=total,
            cap=ECHO_CAP, echo_ether=ECHO_ETHER,
            milestones={
                "m10": total >= RES_MILESTONES[0],
                "m50": total >= RES_MILESTONES[1],
                "m100": total >= RES_MILESTONES[2],
            },
            top=top,
            descendants=[EchoDescendant(**d) for d in desc],
            descendants_total=desc_total,
            apprentice=apprentice,
        )
    finally:
        conn.close()


@app.post("/api/echoes/claim", response_model=EchoesClaimResponse)
def echoes_claim(req: EchoesClaimRequest):
    """Забрать накопленные отголоски эфиром. Вечный счётчик не уменьшается."""
    conn = get_db()
    try:
        claimed, ether, total = _claim_echoes(conn, req.device_id)
        return EchoesClaimResponse(ok=True, claimed=claimed, ether=ether, total=total)
    finally:
        conn.close()


def _letter_row_to_data(row, reveal_before: str, yesterday: str) -> LetterData:
    """Строка письма → ответ клиенту: без слагов, имена дозированно.

    Прогрессия подсказок: сегодня — только длины; вчера — первая буква A;
    ≥2 дней (revealed) — имя A целиком + первая буква B; разгадано — оба.
    """
    solved = bool(row["solved"])
    an, bn = row["a_name"] or "", row["b_name"] or ""
    revealed = (not solved) and row["day"] <= reveal_before
    show_a, show_b, ka, kb = "", "", [], []
    if solved:
        show_a, show_b = an, bn
    elif revealed:
        show_a = an
        if bn:
            kb = [[0, bn[0]]]
    elif row["day"] == yesterday and an:
        ka = [[0, an[0]]]
    return LetterData(
        day=row["day"], a_name=show_a, b_name=show_b,
        len_a=len(an), len_b=len(bn), known_a=ka, known_b=kb,
        hint=row["hint"], solved=solved, revealed=revealed,
    )


@app.get("/api/letter/today", response_model=LettersResponse)
def letter_today(device_id: str = Query("", max_length=128)):
    """Письмо Светика: сегодняшнее (лениво, 1 LLM-запрос) + конверты + счётчик.

    T04: sync `def` — генерация намёка (requests, до 3×30с) идёт в threadpool
    и не блокирует event loop.
    """
    conn = get_db()
    try:
        nick = ""
        if device_id:
            prow = conn.execute(
                "SELECT nick FROM players WHERE device_id = ?", (device_id,)
            ).fetchone()
            if prow and prow["nick"]:
                nick = prow["nick"]
        day = _today()
        today = _ensure_letter(conn, device_id, nick, day) if device_id else None
        reveal_before = _date_minus(LETTER_REVEAL_DAYS)
        yesterday = _date_minus(1)
        backlog = []
        if device_id:
            for r in conn.execute(
                "SELECT day, a, b, a_name, b_name, hint, solved FROM letters "
                "WHERE device_id = ? AND solved = 0 AND day != ? "
                "ORDER BY day DESC LIMIT ?",
                (device_id, day, LETTER_BACKLOG_MAX),
            ).fetchall():
                backlog.append(_letter_row_to_data(r, reveal_before, yesterday))
        solved_total = 0
        if device_id:
            solved_total = conn.execute(
                "SELECT COUNT(*) AS c FROM letters WHERE device_id = ? AND solved = 1",
                (device_id,),
            ).fetchone()["c"]
        return LettersResponse(
            ok=True,
            today=_letter_row_to_data(today, reveal_before, yesterday) if today else None,
            backlog=backlog,
            solved_total=solved_total,
        )
    finally:
        conn.close()


@app.post("/api/letter/solve", response_model=LetterSolveResponse)
def letter_solve(req: LetterSolveRequest):
    """Проверить сваренную пару против неразгаданных писем (сегодня + бэклог).

    Клиент никогда не получает слаги ответа, поэтому матчинг — только здесь.
    Совпало самое раннее письмо с такой парой → solved=1. Повтор той же пары
    (или чужая пара) → matched=false, счётчики не меняются (идемпотентно).
    """
    conn = get_db()
    try:
        want = canonical_pair_key(req.a.strip().lower(), req.b.strip().lower())
        day = ""
        for row in conn.execute(
            "SELECT day, a, b FROM letters "
            "WHERE device_id = ? AND solved = 0 ORDER BY day ASC",
            (req.device_id,),
        ):
            if canonical_pair_key(row["a"], row["b"]) == want:
                day = row["day"]
                break
        matched = False
        if day:
            cur = conn.execute(
                "UPDATE letters SET solved = 1 "
                "WHERE device_id = ? AND day = ? AND solved = 0",
                (req.device_id, day),
            )
            matched = cur.rowcount > 0
            conn.commit()
        total = conn.execute(
            "SELECT COUNT(*) AS c FROM letters WHERE device_id = ? AND solved = 1",
            (req.device_id,),
        ).fetchone()["c"]
        return LetterSolveResponse(
            ok=True, matched=matched, day=day if matched else "",
            solved_total=total,
            milestone=(matched and total > 0 and total % 5 == 0),
        )
    finally:
        conn.close()

@app.get("/api/atlas/today", response_model=AtlasTodayResponse)
def atlas_today(device_id: str = Query("", max_length=128)):
    """Страница Атласа: сегодняшняя общемировая (лениво, 1 LLM-запрос/сутки) + альбом.

    T04: sync `def` — генерация загадки (requests, до 3×30с) идёт в threadpool
    и не блокирует event loop.
    """
    conn = get_db()
    try:
        day = _today()
        today = _ensure_atlas(conn, day)
        data = None
        if today:
            solvers = conn.execute(
                "SELECT COUNT(*) AS c FROM atlas_solves WHERE day = ?", (day,)
            ).fetchone()["c"]
            mine = False
            if device_id:
                mine = conn.execute(
                    "SELECT 1 FROM atlas_solves WHERE device_id = ? AND day = ?",
                    (device_id, day),
                ).fetchone() is not None
            data = AtlasTodayData(
                day=day, riddle=today["riddle"],
                len_a=len(today["a_name"] or ""), len_b=len(today["b_name"] or ""),
                solvers=solvers, solved_by_me=mine,
                a_name=today["a_name"] if mine else "",
                b_name=today["b_name"] if mine else "",
            )
        history = []
        my_days: set = set()
        if device_id:
            my_days = {
                r["day"] for r in conn.execute(
                    "SELECT day FROM atlas_solves WHERE device_id = ?",
                    (device_id,),
                ).fetchall()
            }
        for r in conn.execute(
            "SELECT day, a_name, b_name, riddle FROM atlas_pages "
            "WHERE day < ? ORDER BY day DESC LIMIT ?",
            (day, ATLAS_HISTORY_MAX),
        ).fetchall():
            history.append(AtlasHistoryData(
                day=r["day"], riddle=r["riddle"],
                a_name=r["a_name"], b_name=r["b_name"],
                solved_by_me=r["day"] in my_days,
            ))
        solved_total = 0
        if device_id:
            solved_total = conn.execute(
                "SELECT COUNT(*) AS c FROM atlas_solves WHERE device_id = ?",
                (device_id,),
            ).fetchone()["c"]
        return AtlasTodayResponse(
            ok=True, today=data, history=history, solved_total=solved_total,
        )
    finally:
        conn.close()


@app.post("/api/atlas/solve", response_model=AtlasSolveResponse)
def atlas_solve(req: AtlasSolveRequest):
    """Проверить сваренную пару против сегодняшней страницы Атласа.

    Разгадывается только сегодняшний день (прошлое — альбом, не игра).
    Повтор и чужая пара → matched=false (идемпотентно).
    """
    conn = get_db()
    try:
        day = _today()
        row = conn.execute(
            "SELECT a, b FROM atlas_pages WHERE day = ?", (day,),
        ).fetchone()
        matched = False
        if row and canonical_pair_key(
            req.a.strip().lower(), req.b.strip().lower()
        ) == canonical_pair_key(row["a"], row["b"]):
            cur = conn.execute(
                "INSERT OR IGNORE INTO atlas_solves (device_id, day) VALUES (?, ?)",
                (req.device_id, day),
            )
            matched = cur.rowcount > 0
            conn.commit()
        total = conn.execute(
            "SELECT COUNT(*) AS c FROM atlas_solves WHERE device_id = ?",
            (req.device_id,),
        ).fetchone()["c"]
        return AtlasSolveResponse(
            ok=True, matched=matched, solved_total=total,
            milestone=(matched and total > 0 and total % ATLAS_MILE_EVERY == 0),
        )
    finally:
        conn.close()


@app.get("/api/week/status", response_model=WeekStatusResponse)
def week_status(device_id: str = Query("", max_length=128)):
    """Недельный слой: жила (теги, мои находки/прожилки) + котёл ярмарки."""
    conn = get_db()
    try:
        today = _today_date()  # T06: единая серверная шкала (не локальная дата хоста)
        week = _week_key(today)
        tag1, tag2, spread = _vein_state(conn, week, today)
        my_hits = 0
        my_streaks = 0
        if device_id:
            # Legacy-only read: legacy_vein_hits больше НЕ пишется (vein-скоринг
            # переехал на цикл-модель vein_hits/vein_streaks), но неделя до
            # миграции здесь всё ещё показывается игрокам (backward compat).
            r = conn.execute("SELECT count, streaks FROM legacy_vein_hits WHERE week = ? AND device_id = ?",
                             (week, device_id)).fetchone()
            if r:
                my_hits, my_streaks = r["count"], r["streaks"]
        fair = _fair_ensure(conn, week)
        days = min(today.weekday() + 1, 7)
        apprentice = int(fair["goal"] * 0.1 * days)
        closed = fair["progress"] + apprentice >= fair["goal"]
        my_contrib = 0
        claimed = False
        prev = None
        if device_id:
            c = conn.execute("SELECT count FROM fair_contrib WHERE week = ? AND device_id = ?",
                             (week, device_id)).fetchone()
            my_contrib = c["count"] if c else 0
            claimed = conn.execute("SELECT 1 FROM fair_claims WHERE week = ? AND device_id = ?",
                                   (week, device_id)).fetchone() is not None
            pw = _week_key(_week_monday(week) - timedelta(days=7))
            pc = conn.execute("SELECT count FROM fair_contrib WHERE week = ? AND device_id = ?",
                              (pw, device_id)).fetchone()
            if pc and pc["count"] > 0 and conn.execute(
                    "SELECT 1 FROM fair_claims WHERE week = ? AND device_id = ?",
                    (pw, device_id)).fetchone() is None:
                prow = conn.execute("SELECT * FROM fair_weeks WHERE week = ?", (pw,)).fetchone()
                if prow:
                    pclosed = _fair_virtual(prow["progress"], prow["goal"], 7) >= prow["goal"]
                    if pclosed and pc["count"] >= FAIR_MIN_CONTRIB:
                        prev = {"week": pw, "kind": "regen"}
                    else:
                        prev = {"week": pw, "kind": "ether",
                                "amount": FAIR_CONSOLATION * min(pc["count"], FAIR_CONSOLATION_CAP)}
        return WeekStatusResponse(
            ok=True, week=week,
            vein={"tag1": tag1, "tag2": tag2, "spread": spread,
                  "my_hits": my_hits, "my_streaks": my_streaks, "streak_cap": VEIN_STREAK_CAP},
            fair={"tag": fair["tag"], "goal": fair["goal"], "progress": fair["progress"],
                  "apprentice": apprentice, "closed": closed, "my_contrib": my_contrib,
                  "claimed": claimed, "prev": prev},
        )
    finally:
        conn.close()


@app.post("/api/fair/brew", response_model=FairBrewResponse)
def fair_brew(req: FairBrewRequest):
    """Зачесть варку в котёл ярмарки, если выход пары — с тегом недели.

    Выход сверяется с recipes (античит надуманного out); одна пара считается
    раз в неделю с устройства (антифлуд повторных варок)."""
    from gen_llm import canonical_pair_key
    conn = get_db()
    try:
        today = _today_date()  # T06: единая серверная шкала
        week = _week_key(today)
        fair = _fair_ensure(conn, week)
        pair_key = canonical_pair_key(req.a, req.b)
        out_tag = conn.execute(
            "SELECT e.tag FROM recipes r JOIN elements e ON r.out_id = e.id WHERE r.pair_key = ?",
            (pair_key,),
        ).fetchone()
        counted = False
        if out_tag and out_tag["tag"] == fair["tag"]:
            cur = conn.execute(
                "INSERT OR IGNORE INTO fair_pairs (week, device_id, pair_key) VALUES (?, ?, ?)",
                (week, req.device_id, pair_key),
            )
            if cur.rowcount > 0:
                counted = True
                conn.execute("UPDATE fair_weeks SET progress = progress + 1 WHERE week = ?", (week,))
                conn.execute(
                    """INSERT INTO fair_contrib (week, device_id, count) VALUES (?, ?, 1)
                       ON CONFLICT(week, device_id) DO UPDATE SET count = count + 1""",
                    (week, req.device_id),
                )
                conn.commit()
        fair = _fair_ensure(conn, week)
        days = min(today.weekday() + 1, 7)
        apprentice = int(fair["goal"] * 0.1 * days)
        c = conn.execute("SELECT count FROM fair_contrib WHERE week = ? AND device_id = ?",
                         (week, req.device_id)).fetchone()
        return FairBrewResponse(
            ok=True, counted=counted, progress=fair["progress"], goal=fair["goal"],
            contrib=c["count"] if c else 0,
            closed=fair["progress"] + apprentice >= fair["goal"],
        )
    finally:
        conn.close()


@app.post("/api/fair/claim", response_model=FairClaimResponse)
def fair_claim(req: FairClaimRequest):
    """Забрать награды котла: текущая неделя (если закрыта) + прошлая.

    Закрытый котёл + вклад ≥3 → вечный реген (клиент капает +1.0 суммарно);
    иначе — утешение эфиром 30×вклад (кап 20). Повторный забор запрещён."""
    conn = get_db()
    try:
        today = _today_date()  # T06: единая серверная шкала
        week = _week_key(today)
        prev_week = _week_key(_week_monday(week) - timedelta(days=7))
        grants = []
        for w, days in ((week, min(today.weekday() + 1, 7)), (prev_week, 7)):
            if w == week:
                f = _fair_ensure(conn, w)
            else:
                r = conn.execute("SELECT * FROM fair_weeks WHERE week = ?", (w,)).fetchone()
                if not r:
                    continue
                f = dict(r)
            if conn.execute("SELECT 1 FROM fair_claims WHERE week = ? AND device_id = ?",
                            (w, req.device_id)).fetchone():
                continue
            c = conn.execute("SELECT count FROM fair_contrib WHERE week = ? AND device_id = ?",
                             (w, req.device_id)).fetchone()
            contrib = c["count"] if c else 0
            if contrib == 0:
                continue
            if w == week and _fair_virtual(f["progress"], f["goal"], days) < f["goal"]:
                continue  # текущий котёл ещё варится
            closed = _fair_virtual(f["progress"], f["goal"], days) >= f["goal"]
            if closed and contrib >= FAIR_MIN_CONTRIB:
                grants.append({"week": w, "kind": "regen", "amount": 0})
                conn.execute("INSERT INTO fair_claims (week, device_id, kind) VALUES (?, ?, 'regen')",
                             (w, req.device_id))
            else:
                amount = FAIR_CONSOLATION * min(contrib, FAIR_CONSOLATION_CAP)
                grants.append({"week": w, "kind": "ether", "amount": amount})
                conn.execute("INSERT INTO fair_claims (week, device_id, kind) VALUES (?, ?, 'ether')",
                             (w, req.device_id))
        conn.commit()
        return FairClaimResponse(ok=True, grants=grants)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# T22: серверная валидация платёжных чеков
# ---------------------------------------------------------------------------

def _receipt_hash(token: str) -> str:
    """Отпечаток чека: SHA-256 от UTF-8 токена, hex.

    Это тот же отпечаток, что клиент держит в ключе своего локального журнала
    (UserData._token_key), и тот, что возвращается в ответе: клиент сверяет
    ответ валидатора со своим чеком и не применяет чужой результат."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _receipt_validation_enabled() -> bool:
    """Гейт ворендорной проверки: выключен, пока заданы НЕ И URL, И сервисный
    ключ. Выключенный гейт означает «проверки нет», а не «чек прошёл проверку»."""
    return bool(RECEIPT_VALIDATION_URL.strip()) and bool(RECEIPT_SERVICE_KEY.strip())


def _receipt_error(reason: str) -> dict:
    """Тело отказа /api/receipt/verify: ok=False и verified=False идут в паре с
    причиной всегда. reason — серверное audit-поле (в теле ответа и в БД/логе);
    сам клиент его из 4xx/5xx не читает: net.gd (_on_completed, non-2xx-ветка)
    разбирает тело non-2xx ровно на один строковый ключ "detail" (T28/I-1 —
    для human-readable отказа /api/me), а наш detail — словарь, и он наверх не
    уходит: вверх идёт только «HTTP <код>». Ссылка именем, не строками: чужие
    файлы в номерах строк не фиксируются (конвенция ветки). Поэтому решение о
    выдаче клиент принимает по коду ответа: 4xx — отказ по существу, 5xx —
    fail-safe «валидатор не смог ответить» (в отладочной сборке допускается
    начисление)."""
    return {"ok": False, "verified": False, "reason": reason}


def _validate_receipt_with_vendor(provider: str, sku: str, receipt_token: str) -> dict:
    """Единственная точка, из которой вообще может прийти verified=True.

    Честно о состоянии репозитория: реального вызова Google Play Developer API /
    RuStore API здесь нет (нет сервисных ключей и сети), поэтому функция умеет
    отвечать только «не проверено»:
    * гейт выключен → vendor_validation_disabled;
    * гейт включён, но вызова магазина ещё нет → vendor_validation_not_implemented.
    Ни одна ветка не возвращает verified=True без подтверждения магазина.
    """
    if not _receipt_validation_enabled():
        return {"verified": False, "reason": "vendor_validation_disabled"}
    # TODO(release): реальный вызов магазина вместо этой заглушки —
    #   requests.post(RECEIPT_VALIDATION_URL,
    #                 json={"provider": provider, "sku": sku, "token": receipt_token},
    #                 headers={"Authorization": "Bearer " + RECEIPT_SERVICE_KEY},
    #                 timeout=...)
    #   и разбор ответа в {"verified": bool, "reason": str} (плюс refund/revoke
    #   статусы). Проверялось бы sandbox-покупкой; здесь проверить нечем.
    return {"verified": False, "reason": "vendor_validation_not_implemented"}


@app.post("/api/receipt/verify", response_model=ReceiptVerifyResponse)
def receipt_verify(req: ReceiptVerifyRequest):
    """Проверить чек покупки перед начислением товара (T22).

    Порядок: нормализация → гейт → журнал → вердикт магазина.
    * verified=True приходит либо из вердикта магазина
      (_validate_receipt_with_vendor), либо как эхо уже подтверждённой им же
      записи в журнале; третьего источника нет. При выключенном гейте ответ —
      503 vendor_validation_disabled: отказ, а не «чек валиден». Отказ отдаётся
      и для уже processed-чеков: выключенный валидатор не должен разрешать
      выдачу ни в каком виде (консервативно по правилам задачи);
    * идемпотентность: первый запрос записывает чек как pending, подтверждённый
      становится processed; повтор processed-чека тем же устройством отдаёт
      РОВНО тот же ответ и повторно магазин не дёргает;
    * тот же чек с другим device_id → 409 (чек уже привязан к устройству);
    * тот же токен с другим sku → 409 (receipt_hash — единственный PK, поэтому
      чек нельзя предъявлять за другой товар);
    * тот же токен с другим provider → 409 (по той же причине: чек нельзя
      предъявлять за другой магазин, reason — receipt_provider_mismatch);
    * гонка с anti-spam-зачисткой журнала (startup/_cleanup удаляет старые
      pending-строки) между INSERT и SELECT: прочитанной строки нет → 503
      receipt_journal_read_failed — «валидатор не смог ответить», а не 500;
    * сырой токен в БД не сохраняется, только его SHA-256.

    T04: sync `def` — будущий блокирующий вызов магазина (requests) уходит в
    threadpool Starlette и не замораживает event loop.
    """
    provider = req.provider.strip().lower()
    sku = req.sku.strip()
    token = req.receipt_token.strip()
    device_id = req.device_id.strip()
    if device_id == "":
        raise HTTPException(status_code=400, detail=_receipt_error("empty_device_id"))
    if provider not in RECEIPT_PROVIDERS:
        raise HTTPException(status_code=400, detail=_receipt_error("unknown_provider"))
    if sku not in RECEIPT_SKUS:
        raise HTTPException(status_code=400, detail=_receipt_error("unknown_sku"))
    if token == "":
        raise HTTPException(status_code=400, detail=_receipt_error("empty_receipt_token"))
    if not _receipt_validation_enabled():
        raise HTTPException(status_code=503, detail=_receipt_error("vendor_validation_disabled"))

    receipt_hash = _receipt_hash(token)
    now = time.time()  # T06: epoch-аудит (от TZ не зависит, с днями не сверяется)
    conn = get_db()
    try:
        # INSERT OR IGNORE, а не «прочитал → вставил»: два параллельных запроса
        # одного чека с разных устройств не должны ни пасть на PRIMARY KEY,
        # ни дать проигравшему «ок» — он увидит тот же отказ, что и победитель
        # (тот же принцип атомарного check-and-mark, что в T03/T08).
        conn.execute(
            "INSERT OR IGNORE INTO receipts"
            " (receipt_hash, device_id, provider, sku, status, first_seen_at, last_seen_at)"
            " VALUES (?, ?, ?, ?, 'pending', ?, ?)",
            (receipt_hash, device_id, provider, sku, now, now),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM receipts WHERE receipt_hash = ?", (receipt_hash,)
        ).fetchone()
        if row is None:
            # T28 (Minor): гонка с anti-spam-зачисткой (см. _cleanup-ветку:
            # DELETE протухших pending) между коммитом INSERT и этим SELECT —
            # иначе row["..."] давал бы TypeError → 500. Без строки вердикт
            # вынести нельзя, а это ровно «валидатор не смог ответить» —
            # та же конвенция 503, что у выключенного гейта выше.
            # guarded, untested: кейс не пишется — гонка между двумя execute
            # недетерминирована, а подмена conn-заглушкой проверяла бы только
            # саму заглушку; внешнее прикрытие — статический разбор (TypeError
            # на None в HEAD) и первый реальный прогон pytest на коробке с 3.10.
            raise HTTPException(
                status_code=503,
                detail=_receipt_error("receipt_journal_read_failed"),
            )
        if row["device_id"] != device_id:
            raise HTTPException(
                status_code=409,
                detail={**_receipt_error("receipt_device_mismatch"), "receipt_hash": receipt_hash},
            )
        # R-3: симметрично sku-сверке ниже — receipt_hash единственный PK, поэтому
        # тот же токен, предъявленный с ДРУГИМ provider, иначе получил бы вердикт
        # или echo по чужому провайдеру. Чек привязан к провайдеру, под которым его
        # впервые увидели: несовпадение — отказ (отдельный reason для аудита).
        if row["provider"] != provider:
            raise HTTPException(
                status_code=409,
                detail={**_receipt_error("receipt_provider_mismatch"), "receipt_hash": receipt_hash},
            )
        # M-3: PRIMARY KEY — только receipt_hash, поэтому один и тот же токен,
        # предъявленный с ДРУГИМ sku, находит строку уже другого товара. Без сверки
        # такой запрос получил бы верное echo processed (или вердикт по чужому SKU).
        # Чек привязан к SKU, с которым его впервые увидели: несовпадение — отказ.
        if row["sku"] != sku:
            raise HTTPException(
                status_code=409,
                detail={**_receipt_error("receipt_sku_mismatch"), "receipt_hash": receipt_hash},
            )
        if row["status"] == "processed":
            return ReceiptVerifyResponse(
                ok=True, verified=True, status="processed",
                reason="verified", receipt_hash=receipt_hash,
            )
        verdict = _validate_receipt_with_vendor(provider, sku, token)
        reason = str(verdict.get("reason") or "vendor_rejected")
        if verdict.get("verified") is True:
            conn.execute(
                "UPDATE receipts SET status = 'processed', processed_at = ?, last_seen_at = ?"
                " WHERE receipt_hash = ?",
                (now, now, receipt_hash),
            )
            conn.commit()
            return ReceiptVerifyResponse(
                ok=True, verified=True, status="processed",
                reason="verified", receipt_hash=receipt_hash,
            )
        conn.execute(
            "UPDATE receipts SET last_seen_at = ? WHERE receipt_hash = ?", (now, receipt_hash)
        )
        conn.commit()
        if reason in RECEIPT_UNAVAILABLE_REASONS:
            # «валидатор не смог ответить» — отдельный статус от «магазин чек
            # не подтвердил»: клиент не обязан угадывать конфигурацию сервера.
            raise HTTPException(
                status_code=503,
                detail={**_receipt_error(reason), "receipt_hash": receipt_hash},
            )
        return ReceiptVerifyResponse(
            ok=False, verified=False, status=str(row["status"]),
            reason=reason, receipt_hash=receipt_hash,
        )
    finally:
        conn.close()

# ---------------------------------------------------------------------------
# Запуск
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    
    print(f"Запуск сервера на http://{SERVER_URL}")
    print(f"База данных: {DB_PATH}")
    uvicorn.run("server:app", host="0.0.0.0", port=8080, reload=True)
