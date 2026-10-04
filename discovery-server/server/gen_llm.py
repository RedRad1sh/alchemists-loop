#!/usr/bin/env python3
from __future__ import annotations
"""
LLM-генератор веществ (гибридная схема).

Для неизвестной пары спрашивает языковую модель: есть ли у двух веществ
очевидный результат, который непосредственно объясняется ОБОИМИ входными
элементами. Если модель считает пару бессмысленной — возвращает
«не сочетается» (в игре это «туман рассеялся», элемент не создаётся), и
сервер сохраняет отказ в БД (rejected_pairs).

Ключевой принцип: LLM генерирует новый рецепт ОДИН раз, после чего решение
фиксируется в БД и больше не зависит от доступности или выбора модели.
БД — источник истины. Ручных списков несочетаемых пар в проде НЕТ:
решение о несочетаемости принимает модель (а в заглушке mock — её
детерминированная эмуляция).

LLM решает сочетимость и имя; дополнительно она может предложить glyph,
описание и tag — сервер берёт их только прошедшими валидацию, иначе подставляет
фолбэк. Категория (category) всегда определяется сервером.

Отсылки к мемам, играм, поп-культуре и музыке разрешены, но строго оправданы:
оба вещества должны напрямую и без натяжек указывать на отсылку, а результат —
её каноническое имя. Правила — в SYSTEM_PROMPT (механизм "reference").

Провайдеры (LLM_PROVIDER):
  local (по умолчанию) — детерминированный локальный генератор: только очевидные,
                      непосредственно объяснимые ОБОИМИ веществами пары из
                      курируемой таблицы LOCAL_OBVIOUS; всё остальное — «туман»
                      (combinable:false). Не требует сети и ключа.
  openrouter        — https://openrouter.ai (бесплатные :free-модели, ротация)
  openai_compatible — любой OpenAI-совместимый эндпоинт (Groq, Together,
                      Fireworks, Cerebras, Mistral, Ollama и т.п.) через LLM_BASE_URL
  mock              — детерминированная заглушка для тестов (без сети)
  off               — LLM выключен (всегда «unavailable»)

Ротация моделей сохраняется: модели из LLM_MODELS перебираются по кругу.
"""

import json
import logging
import os
import re
import time

import requests

log = logging.getLogger("alchemy.llm")


def _load_dotenv(paths=None) -> None:
    """Минимальный .env-лоадер без зависимостей: строки KEY=VALUE.

    Загружает переменные из файла(ов) .env ПЕРЕД чтением конфигурации.
    Реальное окружение главнее: если переменная уже задана (export в шелле,
    systemd и т.п.), значение из файла её НЕ перезаписывает. Поддержка:
    комментарии (#), кавычки, префикс `export `.
    """
    if paths is None:
        here = os.path.dirname(os.path.abspath(__file__))
        paths = (os.path.join(here, ".env"),)
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if line.startswith("export "):
                        line = line[7:].lstrip()
                    if "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    k = k.strip()
                    v = v.strip()
                    if v[:1] in ('"', "'"):
                        # кавычки защищают решётку внутри значения
                        q = v[0]
                        end = v.find(q, 1)
                        v = v[1:end] if end != -1 else v[1:].strip(q)
                    else:
                        # unquoted: « #» начинает inline-комментарий
                        v = v.split(" #", 1)[0].rstrip()
                        v = v.strip('"').strip("'")
                    if k and k not in os.environ:
                        os.environ[k] = v
        except FileNotFoundError:
            pass


# Подхватываем .env рядом с gen_llm.py (тот же каталог, что и server.py).
_load_dotenv()

# Сколько попыток генерации на пару (форматные и семантические retry вместе).
# Уменьшите через LLM_MAX_ATTEMPTS, чтобы недоступная LLM отваливалась быстрее.
MAX_ATTEMPTS = int(os.environ.get("LLM_MAX_ATTEMPTS", "3"))

# Дефолтный пул бесплатных моделей OpenRouter. Список free-моделей регулярно
# меняется: сверяться с https://openrouter.ai/api/v1/models (фильтр ":free").
# Актуально на 2026-09-11. Ротация размазывает лимиты. Если какая-то модель
# начала отвечать 404 — обновите список (в логе будет «HTTP 404 ... model not found»).
# Локальный генератор (провайдер local): курируемая таблица ОЧЕВИДНЫХ пар.
# Ключ — canonical_pair_key (слаги, отсортированы). Результат непосредственно
# объясним ОБОИМИ входными веществами; всё остальное — «туман». Это не
# случайный fallback-пул: решение фиксируется в БД так же, как решение LLM.
LOCAL_OBVIOUS = {
    "air|air": "Ветер",
    "air|storm": "Ураган",
    "bird|tree": "Гнездо",
    "boat|person": "Моряк",
    "coal|metal": "Сталь",
    "desert|plant": "Кактус",
    "desert|water": "Оазис",
    "fire|forest": "Пожар",
    "fish|person": "Рыбак",
    "house|house": "Деревня",
    "house|person": "Семья",
    "ice|mountain": "Ледник",
    "ice|storm": "Метель",
    "lightning|sky": "Гроза",
    "metal|water": "Ржавчина",
    "mountain|snow": "Лавина",
    "person|snow": "Снеговик",
    "sand|water": "Пляж",
    "storm|water": "Шторм",
    "tool|wood": "Топор",
    "wall|wall": "Крепость",
    "water|water": "Озеро",
}


def _local_result(a_slug: str, b_slug: str) -> dict:
    """Детерминированный локальный генератор: очевидная пара или «туман»."""
    key = canonical_pair_key(a_slug, b_slug)
    name = LOCAL_OBVIOUS.get(key)
    if name:
        return {"combinable": True, "name": name}
    return {"combinable": False}


DEFAULT_MODELS = ",".join([
    "google/gemma-4-31b-it:free",
    "nvidia/nemotron-3-super-120b-a12b:free",
    "google/gemma-4-26b-a4b-it:free",
    "nex-agi/nex-n2.5-pro:free",
    "thinkingmachines/inkling:free",
    "liquid/lfm-2.5-2.6b:free",
])

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# Теги стихий/природы результата (v30, недельный слой: жила и ярмарка выбирают
# тег недели из этого словаря). Модель выбирает ОДИН ближайший по природе.
TAGS = frozenset({
    "огонь", "вода", "земля", "воздух", "свет", "тьма",
    "металл", "камень", "трава", "зверь", "небо", "лёд",
})

# Допустимые ключи глифов — ровно те же 57, что рисует клиент
# (game/element_glyphs.gd GLYPH_KEYS). Модель выбирает глиф ТОЛЬКО из этого
# списка; иначе сервер подставляет глиф по категории.
GLYPHS = frozenset({
    "fire", "water", "earth", "air", "steam", "stone", "clay", "dust", "spark",
    "mist", "brick", "sand", "glass", "plant", "cloud", "ice", "mountain", "mud",
    "metal", "life", "smoke", "lava", "sky", "rain", "storm", "hail", "snow",
    "volcano", "obsidian", "magma", "ash", "gold", "swamp", "fish", "bird",
    "beast", "person", "seed", "grass", "mushroom", "lightning", "tornado",
    "tool", "tree", "sun", "crystal", "sandstorm", "forest", "wood", "flower",
    "rainbow", "desert", "boat", "coal", "wall", "house", "child",
})

# Параметрические глифы: модель может САМА составить иконку результата как
# «форма+число» (например star6, crystal5, ring3). Число — в диапазоне формы.
# Клиент рисует эти формы процедурно (game/element_glyphs.gd PARAM_BASES) —
# так новые вещества перестают повторять одни и те же иконки.
GLYPH_PARAM = {
    "poly": (3, 9),      # многоугольник: 3..9 углов
    "star": (4, 10),     # звезда: 4..10 лучей
    "burst": (5, 12),    # расходящиеся лучи
    "ring": (2, 5),      # концентрические кольца
    "cluster": (3, 7),   # гроздь кругов
    "crystal": (3, 7),   # сросток кристаллов
    "blossom": (4, 9),   # лепестки вокруг сердцевины
    "sigil": (3, 8),     # рунические пересекающиеся линии
    "spiral": (2, 4),    # спираль: число витков
    "rays": (5, 12),     # лучи + дуга (солнце/сияние)
}
GLYPH_PARAM_RE = re.compile(r"^(poly|star|burst|ring|cluster|crystal|blossom|sigil|spiral|rays)(\d+)$")


def is_glyph(glyph: str) -> bool:
    """Валиден ли глиф: именованный ключ или параметрический «форма+число»."""
    if glyph in GLYPHS:
        return True
    m = GLYPH_PARAM_RE.match(glyph)
    if not m:
        return False
    base, n = m.group(1), int(m.group(2))
    lo, hi = GLYPH_PARAM[base]
    return lo <= n <= hi

SYSTEM_PROMPT = """\
Ты — генератор результатов для логической игры-алхимии (жанр Little Alchemy 2).
Это НЕ игра свободных ассоциаций и НЕ Infinite Craft.

Твой ответ — РОВНО один JSON-объект и ничего больше: без пояснений, без текста
до/после, без обёрток в ```, без слова «вот». Формат строго:
{"combinable": true, "name": "Дом", "glyph": "house", "description": "...", "tag": "камень"}
или
{"combinable": false}

tag — ОДНО слово из списка (природа результата, ближайшая по смыслу): огонь,
вода, земля, воздух, свет, тьма, металл, камень, трава, зверь, небо, лёд.

glyph — иконка результата. Допустимы два вида:
1) готовый образ из списка (самый узнаваемый; если точного нет — ближайший по
смыслу): fire, water, earth, air, steam, stone, clay, dust, spark, mist, brick,
sand, glass, plant, cloud, ice, mountain, mud, metal, life, smoke, lava, sky,
rain, storm, hail, snow, volcano, obsidian, magma, ash, gold, swamp, fish, bird,
beast, person, seed, grass, mushroom, lightning, tornado, tool, tree, sun,
crystal, sandstorm, forest, wood, flower, rainbow, desert, boat, coal, wall,
house, child.
2) ПАРАМЕТРИЧЕСКИЙ глиф «форма+число» — сам придумай силуэт результата:
poly(3-9), star(4-10), burst(5-12), ring(2-5), cluster(3-7), crystal(3-7),
blossom(4-9), sigil(3-8), spiral(2-4), rays(5-12).
Примеры: "star6" — шестилучевая звезда, "crystal5" — пять кристаллов, "ring3" —
три кольца, "poly8" — восьмиугольник, "spiral3" — тройная спираль, "sigil4" —
четыре руны. Подбирай форму и число под силуэт вещества и НЕ повторяй один глиф
для разных результатов, когда подходит другой.
description — одна короткая фраза на русском (до 25 слов), лорно описывающая
результат: как он рождён этими двумя веществами. Без дефисов-переносов и без
имени результата в начале. Пример для Огонь+Вода: "Вода, вскипевшая под жаром,
поднялась в воздух невидимым дыханием."

Ставь combinable=true, только если у двух входных понятий есть прямой,
общеизвестный, одношаговый результат, непосредственно объяснимый ОБОИМИ
понятиями. Допустимые механизмы:
- construction — части образуют целое или конструкцию:
  Кирпич+Кирпич=Стена, Кирпич+Стена=Дом, Стена+Стена=Комната;
- group — два объекта образуют пару, группу или множество:
  Человек+Человек=Пара, Рыба+Рыба=Стая, Дерево+Дерево=Роща;
- mixture — общеизвестная смесь или состояние веществ:
  Вода+Пыль=Грязь, Вода+Вода=Лужа;
- interaction — очевидное физическое взаимодействие:
  Огонь+Вода=Пар, Лёд+Огонь=Вода;
- reference — ОБА понятия вместе прямо и недвусмысленно отсылают к известному
  явлению поп-культуры (мем, игра, фильм, музыка), и результат — каноническое
  имя этой отсылки (пример: Кольцо+Магия=Кольцо Всевластия).

Правила:
1. В результате должны участвовать ОБА входных понятия.
2. Тест на удаление: замени любой вход случайным понятием — результат должен
   перестать следовать. Иначе связь ложная.
3. Запрещены скрытые инструменты, условия, ожидание и цепочки из двух и более шагов.
4. Запрещено выводить результат только из совпадения категорий входов.
5. Одинаковые входы — это ДВЕ КОПИИ одного объекта: допустима конструкция, пара
   или группа (Стена+Стена=Комната), но не превращение в постороннее вещество
   (Стена+Стена=Ртуть — ЗАПРЕЩЕНО).
6. Отсылки разрешены, только если сильно оправданы (см. механизм reference).
   Слабая или натянутая отсылка — не повод: верни combinable=false.
7. Сомневаешься — верни {"combinable": false}. Честный отказ лучше натянутого
   результата.
8. name — конкретное русское слово или словосочетание из 1-4 слов, именительный
   падеж, только кириллица и пробелы, с заглавной буквы, БЕЗ дефисов, цифр и
   латиницы.
9. glyph — из приведённого списка образов ИЛИ параметрический (форма+число в
   указанном диапазоне); description — до 25 слов, кириллица, без цифр в начале,
   без "name:" и без обёрток.
10. tag — ровно одно слово из списка выше (не выдумывай своих); не уверен —
    бери тег dominantного входа (огонь/вода/земля/воздух).

Примеры ответов:
Кирпич+Кирпич -> {"combinable": true, "name": "Стена", "glyph": "wall", "description": "Кирпичи, уложенные в ряд, стали преградой.", "tag": "камень"}
Огонь+Вода    -> {"combinable": true, "name": "Пар", "glyph": "steam", "description": "Вода, вскипевшая под жаром, поднялась в воздух.", "tag": "вода"}
Камень+Камень -> {"combinable": false}
Птица+Пепел   -> {"combinable": false}
"""

# Промпт отдельного этапа семантической проверки кандидата.
VALIDATOR_PROMPT = """\
Ты — строгий проверяющий для игры-алхимии. Даны два вещества и кандидат-результат.
Ответь {"valid": true}, только если результат — САМЫЙ очевидный и непосредственно
объясним ОБОИМИ входными веществами: прямой физический/природный результат,
очевидное построение или взаимодействие, естественная пара/группа. Отсылка к
поп-культуре, игре, мему или музыке допустима, только если ОБА вещества напрямую
и без натяжек указывают на неё и результат — каноническое имя отсылки.
Если результат натянут, связан в основном с одним веществом, требует цепочки
ассоциаций или натянутой отсылки — {"valid": false}.
Верни ровно один JSON-объект и ничего больше.
"""

# Сообщения обратной связи для retry (раздельные каналы).
FORMAT_FEEDBACK = (
    "Ответ не соответствует формату. Верни СТРОГО один JSON-объект и ничего больше: "
    '{"combinable": true, "name": "Имя"} или {"combinable": false}.'
)

SEMANTIC_FEEDBACK = (
    "Предыдущий кандидат «%s» семантически не подходит (%s). "
    "Выбери другой, более очевидный результат, непосредственно объяснимый ОБОИМИ веществами. "
    "Если подходящего результата нет — {\"combinable\": false}."
)

# Письмо Светика (v27): короткий уютный намёк-загадка на заданную пару.
HINT_SYSTEM_PROMPT = """\
Ты — Светик, маленький светлячок-алхимик. Напиши короткий (1–2 предложения, до 40 слов) \
тёплый намёк-загадку на пару веществ, переданную пользователем. \
НЕ называй оба вещества прямо: опиши их образно, через ощущения и свойства. \
Текст только на русском. Верни СТРОГО один JSON-объект: {"hint": "текст намёка"}."""

HINT_FORMAT_FEEDBACK = (
    "Ответ не соответствует формату. Верни СТРОГО один JSON-объект и ничего больше: "
    '{"hint": "тёплый намёк на пару, 1–2 предложения"}.'
)


class LLMError(Exception):
    """Модель недоступна / не смогла дать валидный ответ."""


def canonical_pair_key(a: str, b: str) -> str:
    if a == b:
        return f"{a}|{a}"
    return f"{min(a, b)}|{max(a, b)}"


def _extract_json(text: str) -> dict | None:
    """Вытащить первый валидный JSON-объект из ответа модели.

    Reasoning-модели часто добавляют текст до/после JSON или оборачивают его
    в ```json. Пробуем по очереди: весь текст, без ```-обёртки, от первой {
    до последней }, и, если есть хвост после JSON, — прогрессивное усечение
    по каждой закрывающей скобке.
    """
    if not text:
        return None
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\s*", "", text)
        text = re.sub(r"\s*```\s*$", "", text).strip()

    def _load(candidate: str):
        try:
            return json.loads(candidate)
        except (json.JSONDecodeError, ValueError):
            return None

    res = _load(text)
    if isinstance(res, dict):
        return res
    start = text.find("{")
    if start == -1:
        return None
    # перебираем закрывающие скобки справа налево: так хвостовой текст
    # после JSON не мешает разбору
    pos = len(text)
    while True:
        end = text.rfind("}", start, pos)
        if end == -1:
            return None
        res = _load(text[start:end + 1])
        if isinstance(res, dict):
            return res
        pos = end


def _http_error_text(r) -> str:
    """Короткое и понятное описание HTTP-ошибки OpenRouter/OpenAI.

    OpenRouter отдаёт {"error": {"message": ..., "code": ...}}; вытаскиваем
    именно message/code, а не сырое тело.
    """
    try:
        body = r.json()
        err = body.get("error") or {}
        msg = err.get("message") or body.get("message") or body.get("detail")
        code = err.get("code") or body.get("code")
        if msg:
            return f"{code} {msg}" if code else str(msg)
    except ValueError:
        pass
    return r.text[:200]


def validate_result(res: dict) -> dict | None:
    """Только ТЕХНИЧЕСКАЯ проверка ответа модели. None — ответ невалиден.

    Проверяет: это объект; поле combinable; имя — корректное русское слово
    без цифр/латиницы/дефисов, допустимой длины. Семантику НЕ оценивает —
    для этого есть отдельный этап (semantic_check / LLM-валидатор).
    """
    if not isinstance(res, dict):
        return None
    comb = res.get("combinable")
    # некоторые модели отвечают строками "true"/"false" — приводим к bool
    if isinstance(comb, str):
        if comb.strip().lower() in ("true", "1", "yes"):
            comb = True
        elif comb.strip().lower() in ("false", "0", "no"):
            comb = False
    if comb is False:
        return {"combinable": False}
    if comb is not True:
        return None
    name = str(res.get("name", "")).strip()
    if not name or len(name) > 40:
        return None
    if "-" in name or "_" in name or any(ch.isdigit() for ch in name):
        return None
    if not any(("а" <= ch <= "я") or ("А" <= ch <= "Я") or ch in "ёЁ" for ch in name):
        return None
    out = {"combinable": True, "name": name}
    # глиф — именованный ключ или параметрический «форма+число» (иначе сервер
    # сам подставит подходящий глиф)
    glyph = str(res.get("glyph", "")).strip().lower()
    if is_glyph(glyph):
        out["glyph"] = glyph
    # описание — лор от модели; мягко чистим
    desc = str(res.get("description", "")).strip()
    desc = desc.replace("\n", " ").replace("\r", " ")
    desc = " ".join(desc.split())
    if desc and not any(ch.isdigit() for ch in desc[:1]):
        out["description"] = desc[:160]
    # тег — только из словаря (иначе сервер выведет его из категории)
    tag = str(res.get("tag", "")).strip().lower()
    if tag in TAGS:
        out["tag"] = tag
    return out


def validate_hint(res: dict) -> dict | None:
    """Техническая проверка намёка для письма: {"hint": "..."}. None — невалиден."""
    if not isinstance(res, dict):
        return None
    hint = str(res.get("hint", "")).strip().replace("\n", " ").replace("\r", " ")
    hint = " ".join(hint.split())
    if len(hint) < 8 or len(hint) > 400:
        return None
    return {"hint": hint}


# Совпадение кандидата с ингредиентом (огонь+уголь=уголь) — НЕ повод для ретраев:
# generate() отдаёт такое имя как есть, а сервер привязывает пару
# к существующему веществу через дедупликацию имён (_link_existing).
SAME_AS_INGREDIENT = "совпадает с одним из ингредиентов"


def semantic_check(name: str, a_name: str, b_name: str) -> tuple[bool, str]:
    """Детерминированные семантические guardrail'ы (без сети). (ok, reason).

    Отсекают очевидный мусор, не зависящий от «здравого смысла» модели:
    совпадение с ингредиентом и механическую склейку обоих имён.
    Полноценную семантическую проверку делает LLM-валидатор (отдельный этап).
    """
    nl = " ".join(name.strip().lower().split())
    al = a_name.strip().lower()
    bl = b_name.strip().lower()
    if nl == al or nl == bl:
        return False, SAME_AS_INGREDIENT
    compact = nl.replace(" ", "")
    if compact in (al + bl, bl + al):
        return False, "механическая склейка ингредиентов"
    return True, ""


def _with_flavor(out: dict, valid: dict) -> dict:
    """Протащить глиф и описание от модели в результат (были в validate_result,
    но generate() их выкидывал — сервер всегда падал на фолбэк)."""
    if valid.get("glyph"):
        out["glyph"] = valid["glyph"]
    if valid.get("description"):
        out["description"] = valid["description"]
    if valid.get("tag"):
        out["tag"] = valid["tag"]
    return out


class LLMGenerator:
    def __init__(self, provider: str | None = None, api_key: str | None = None,
                 models: str | None = None, base_url: str | None = None,
                 timeout: float | None = None):
        self.provider = (provider or os.environ.get("LLM_PROVIDER", "local")).strip().lower()
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY") or os.environ.get("LLM_API_KEY", "")
        self.base_url = (base_url or os.environ.get("LLM_BASE_URL", "")).strip()
        self.timeout = timeout if timeout is not None else float(os.environ.get("LLM_TIMEOUT", "30"))
        raw = models if models is not None else os.environ.get("LLM_MODELS", DEFAULT_MODELS)
        self.models = [m.strip() for m in raw.split(",") if m.strip()]
        self._rot = 0

    def available(self) -> bool:
        if self.provider in ("off", ""):
            return False
        if self.provider in ("mock", "local"):
            return True
        return bool(self.api_key)

    # ------------------------------------------------------------------
    def generate(self, a_slug: str, b_slug: str, a_name: str, b_name: str,
                 pair_key: str) -> dict:
        """Вернуть {"combinable": False} | {"combinable": True, "name": "..."}.

        - LLM недоступна (сеть/ключ/429/битый формат у всех моделей) → LLMError:
          сервер вернёт status="unavailable", пара останется кандидатом.
        - Модель ЯВНО ответила combinable:false → {"combinable": False} — пара
          сохраняется в БД как rejected. Технический сбой НЕ считается отказом.
        """
        if self.provider == "off":
            raise LLMError("LLM выключен (LLM_PROVIDER=off)")
        if self.provider == "local":
            return _local_result(a_slug, b_slug)
        if self.provider == "mock":
            return self._mock(a_slug, b_slug, a_name, b_name, pair_key)

        if not self.api_key:
            raise LLMError("нет API-ключа (OPENROUTER_API_KEY/LLM_API_KEY)")
        if not self.models:
            raise LLMError("нет моделей (LLM_MODELS)")

        t_start = time.time()
        log.info("пара «%s» + «%s»: генерирую (провайдер %s, модели: %s)",
                 a_name, b_name, self.provider, ", ".join(self.models))
        feedback = ""
        errors: list[str] = []
        for attempt in range(MAX_ATTEMPTS):
            model = self.models[(self._rot + attempt) % len(self.models)]
            try:
                raw = self._call_once(model, a_name, b_name, feedback)
            except LLMError as e:
                log.warning("попытка %d/%d: %s → %s", attempt + 1, MAX_ATTEMPTS, model, e)
                errors.append(f"{model}: {e}")
                continue

            valid = validate_result(_extract_json(raw))
            if valid is None:
                # форматная ошибка → retry с требованием строгого JSON.
                # Важно: это НЕ «не сочетается» — пара не помечается отказом.
                log.warning("попытка %d/%d: %s → ответ не по формату", attempt + 1, MAX_ATTEMPTS, model)
                log.warning("  сырой ответ модели: %r", raw[:500])
                feedback = FORMAT_FEEDBACK
                errors.append(f"{model}: ответ не соответствует формату")
                continue
            if valid.get("combinable") is False:
                self._rot = (self._rot + attempt + 1) % len(self.models)
                log.info("пара «%s» + «%s»: модель решила «не сочетается» (%.1fs)",
                         a_name, b_name, time.time() - t_start)
                return {"combinable": False}

            name = valid["name"]
            ok, reason = self._semantic_validate(name, a_name, b_name)
            if not ok and reason == SAME_AS_INGREDIENT:
                # кандидат совпал с ингредиентом (огонь+уголь=уголь): ретраи
                # бессмысленны — отдаём как есть, сервер привяжет пару
                # к существующему веществу по имени
                self._rot = (self._rot + attempt + 1) % len(self.models)
                log.info("пара «%s» + «%s» → «%s» (совпал с ингредиентом, без ретраев)",
                         a_name, b_name, name)
                return _with_flavor({"combinable": True, "name": name}, valid)
            if not ok:
                # семантическая ошибка → retry с инструкцией выбрать другой кандидат
                log.warning("кандидат «%s» отклонён: %s → пробую другой", name, reason)
                feedback = SEMANTIC_FEEDBACK % (name, reason)
                errors.append(f"{model}: кандидат «{name}» отклонён ({reason})")
                continue

            self._rot = (self._rot + attempt + 1) % len(self.models)
            log.info("пара «%s» + «%s» → «%s» (модель %s, %.1fs)",
                     a_name, b_name, name, model, time.time() - t_start)
            return _with_flavor({"combinable": True, "name": name}, valid)

        # Ни одна модель не дала валидного ответа (сеть/429/битый формат).
        # Это технический сбой: НЕ помечаем пару как «не сочетается» — она
        # остаётся кандидатом и будет сгенерирована позже (сервер вернёт
        # status="unavailable").
        log.error("пара «%s» + «%s»: генерация не удалась (%.1fs): %s",
                  a_name, b_name, time.time() - t_start, "; ".join(errors))
        raise LLMError("; ".join(errors) or "нет ответа от моделей")

    # ------------------------------------------------------------------
    def generate_hint(self, a_name: str, b_name: str) -> dict:
        """Намёк-загадка на пару для «Письма Светика». Вернуть {"hint": "..."}.

        1 запрос в сутки на игрока (кэшируется сервером в таблице letters).
        LLMError → письмо откладывается: сервер вернёт today=null, а игрок
        почитает конверты из запаса. Несгоревший день догенерируется позже.
        """
        if self.provider == "off":
            raise LLMError("LLM выключен (LLM_PROVIDER=off)")
        if self.provider in ("mock", "local"):
            return {"hint": self._template_hint(a_name, b_name)}
        if not self.api_key:
            raise LLMError("нет API-ключа (OPENROUTER_API_KEY/LLM_API_KEY)")
        if not self.models:
            raise LLMError("нет моделей (LLM_MODELS)")

        t_start = time.time()
        log.info("намёк на «%s» + «%s»: генерирую", a_name, b_name)
        feedback = ""
        errors: list[str] = []
        for attempt in range(MAX_ATTEMPTS):
            model = self.models[(self._rot + attempt) % len(self.models)]
            try:
                raw = self._call_hint_once(model, a_name, b_name, feedback)
            except LLMError as e:
                log.warning("намёк %d/%d: %s → %s", attempt + 1, MAX_ATTEMPTS, model, e)
                errors.append(f"{model}: {e}")
                continue
            valid = validate_hint(_extract_json(raw))
            if valid is None:
                log.warning("намёк %d/%d: %s → ответ не по формату", attempt + 1, MAX_ATTEMPTS, model)
                feedback = HINT_FORMAT_FEEDBACK
                errors.append(f"{model}: ответ не соответствует формату")
                continue
            self._rot = (self._rot + attempt + 1) % len(self.models)
            log.info("намёк на «%s» + «%s» готов (модель %s, %.1fs)",
                     a_name, b_name, model, time.time() - t_start)
            return valid
        log.error("намёк на «%s» + «%s»: не удался (%.1fs): %s",
                  a_name, b_name, time.time() - t_start, "; ".join(errors))
        raise LLMError("; ".join(errors) or "нет ответа от моделей")

    def _template_hint(self, a_name: str, b_name: str) -> str:
        """Детерминированный намёк без LLM (mock/local, тесты, офлайн)."""
        a0 = (a_name.strip()[:1] or "?").upper()
        b0 = (b_name.strip()[:1] or "?").upper()
        return (
            f"Мне снилось, как «{a0}…» обнимает «{b0}…». "
            "Попробуй соединить их в котле!"
        )

    def _call_hint_once(self, model: str, a_name: str, b_name: str, feedback: str) -> str:
        """Один вызов модели за намёком; вернуть сырой текст (или LLMError)."""
        t0 = time.time()
        messages = [
            {"role": "system", "content": HINT_SYSTEM_PROMPT},
            {"role": "user", "content": f"Пара: «{a_name}» и «{b_name}»."},
        ]
        if feedback:
            messages.append({"role": "user", "content": feedback})
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 512,
            "max_completion_tokens": 512,
            "reasoning_effort": "none",
            "response_format": {"type": "json_object"},
        }
        url, headers = self._endpoint(model)
        try:
            r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        except requests.RequestException as e:
            raise LLMError(f"сеть: {e.__class__.__name__} (за %.1fs)" % (time.time() - t0)) from e
        if r.status_code == 400 and any(
            key in r.text.lower()
            for key in ("response_format", "json", "reasoning", "max_tokens", "unsupported")
        ):
            payload.pop("response_format", None)
            payload.pop("reasoning_effort", None)
            payload.pop("max_completion_tokens", None)
            try:
                r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
            except requests.RequestException as e:
                raise LLMError(f"сеть: {e.__class__.__name__} (за %.1fs)" % (time.time() - t0)) from e
        if r.status_code != 200:
            raise LLMError(f"HTTP {r.status_code}: {_http_error_text(r)} (за %.1fs)" % (time.time() - t0))
        try:
            content = r.json()["choices"][0]["message"]["content"]
        except (KeyError, IndexError, ValueError) as e:
            raise LLMError("неожиданный формат ответа") from e
        log.info("%s: намёк 200 OK за %.1fs", model, time.time() - t0)
        return content

    def _semantic_validate(self, name: str, a_name: str, b_name: str) -> tuple[bool, str]:
        """Отдельный этап семантической проверки кандидата. (ok, reason).

        Сначала детерминированные guardrail'ы, затем — строгая LLM-проверка
        (пропускается для mock/off и при недоступной сети — тогда решение
        принимается по guardrail'ам и self-check'у в основном промпте).
        """
        ok, reason = semantic_check(name, a_name, b_name)
        if not ok:
            return ok, reason
        if self.provider in ("mock", "off") or not self.api_key or not self.models:
            return True, ""

        user_text = f"Вещества: «{a_name}» и «{b_name}». Кандидат: «{name}»."
        for model in self.models:
            payload = {
                "model": model,
                "messages": [
                    {"role": "system", "content": VALIDATOR_PROMPT},
                    {"role": "user", "content": user_text},
                ],
                "temperature": 0.2,
                "max_tokens": 512,
                "max_completion_tokens": 512,
                "reasoning_effort": "none",
                "response_format": {"type": "json_object"},
            }
            url, headers = self._endpoint(model)
            try:
                r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
            except requests.RequestException:
                continue
            if r.status_code != 200:
                continue
            try:
                content = r.json()["choices"][0]["message"]["content"]
            except (KeyError, IndexError, ValueError):
                continue
            j = _extract_json(content)
            if isinstance(j, dict) and isinstance(j.get("valid"), bool):
                if j["valid"]:
                    log.info("валидатор: «%s» прошёл проверку", name)
                    return True, ""
                log.info("валидатор отклонил «%s»", name)
                return False, "не проходит строгую семантическую проверку"
        # валидатор недоступен — принимаем по guardrail'ам
        return True, ""

    # ------------------------------------------------------------------
    def _call_once(self, model: str, a_name: str, b_name: str, feedback: str) -> str:
        """Один вызов модели; вернуть сырой текст ответа (или LLMError)."""
        t0 = time.time()
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _user_prompt(a_name, b_name)},
        ]
        if feedback:
            messages.append({"role": "user", "content": feedback})
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 512,
            "max_completion_tokens": 512,
            "reasoning_effort": "none",
            "response_format": {"type": "json_object"},
        }
        url, headers = self._endpoint(model)
        try:
            r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        except requests.RequestException as e:
            raise LLMError(f"сеть: {e.__class__.__name__} (за %.1fs)" % (time.time() - t0)) from e
        # Часть провайдеров не умеет response_format=json_object, reasoning-поля
        # (max_completion_tokens/reasoning_effort) или заваливает JSON-валидацию
        # (400 json_validate_failed) → повторяем в «совместимом» виде без них.
        if r.status_code == 400 and any(
            key in r.text.lower()
            for key in ("response_format", "json", "reasoning", "max_tokens", "unsupported")
        ):
            log.info("%s: 400 (%s…) — повторяю в совместимом виде",
                     model, r.text.strip()[:80].replace("\n", " "))
            payload.pop("response_format", None)
            payload.pop("reasoning_effort", None)
            payload.pop("max_completion_tokens", None)
            try:
                r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
            except requests.RequestException as e:
                raise LLMError(f"сеть: {e.__class__.__name__} (за %.1fs)" % (time.time() - t0)) from e
        if r.status_code != 200:
            raise LLMError(f"HTTP {r.status_code}: {_http_error_text(r)} (за %.1fs)" % (time.time() - t0))
        try:
            content = r.json()["choices"][0]["message"]["content"]
        except (KeyError, IndexError, ValueError) as e:
            raise LLMError("неожиданный формат ответа") from e
        log.info("%s: 200 OK за %.1fs", model, time.time() - t0)
        if os.environ.get("ALCHEMY_LOG_RAW") == "1":
            log.info("%s: сырой ответ: %r", model, content[:400])
        return content

    def _endpoint(self, model: str):
        if self.provider == "openrouter":
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": os.environ.get("LLM_HTTP_REFERER", "https://localhost"),
                "X-Title": "Alchemist Loop",
            }
            return OPENROUTER_URL, headers
        # openai_compatible
        base = self.base_url.rstrip("/")
        if not base:
            raise LLMError("для openai_compatible нужен LLM_BASE_URL")
        if base.endswith("/chat/completions"):
            url = base
        elif base.endswith("/v1"):
            url = base + "/chat/completions"
        else:
            url = base + "/chat/completions"
        headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}
        return url, headers

    # ------------------------------------------------------------------
    # Заглушка mock — детерминированная эмуляция «решения модели» для тестов.
    # Это НЕ продакшен-список несочетаемых пар: он описывает поведение
    # вымышленной модели (в т.ч. её отказы), а не правила сервера.
    _MOCK_OBVIOUS = {
        "brick|brick": "Стена",
        "wall|wall": "Дом",
        "fire|water": "Пар",
        "earth|water": "Грязь",
    }
    _MOCK_NONSENSE = {
        "gold|person",  # тестовая «туманная» пара — эмуляция combinable:false
    }

    def _mock(self, a_slug: str, b_slug: str, a_name: str, b_name: str, pair_key: str) -> dict:
        key = canonical_pair_key(a_slug, b_slug)
        if key in self._MOCK_NONSENSE:
            return {"combinable": False}
        if key in self._MOCK_OBVIOUS:
            return {"combinable": True, "name": self._MOCK_OBVIOUS[key]}
        # канонический порядок, чтобы порядок ингредиентов не влиял на имя
        first, second = (a_name, b_name) if a_slug <= b_slug else (b_name, a_name)
        return {"combinable": True, "name": first + second}


def _user_prompt(a_name: str, b_name: str) -> str:
    return (
        f"Соедини «{a_name}» и «{b_name}».\n"
        "Если очевидного, непосредственно объяснимого обоими веществами результата нет — "
        '{"combinable": false}.'
    )
