#!/usr/bin/env python3
"""
Стартовый граф веществ и рецептов сервера первооткрытий.

Полная копия локального графа игры (57 веществ / 53 рецепта): сервер знает
все уже известные вещества и не генерирует для них странные новые имена —
генерация включается только для действительно неизвестных пар. У каждого
вещества есть семантический «glyph» (ключ векторного символа) и краткое
описание «d» — тот же словарь, что и на клиенте (game/element_glyphs.gd).
"""

# slug -> (имя, цвет, слой, категория, glyph, описание)
ITEMS = {
    "fire": ("Огонь", "#ff936b", 0, "огонь", "fire", "Жар и пламя — первостихия."),
    "water": ("Вода", "#71bfff", 0, "вода", "water", "Текучая влага — первостихия."),
    "earth": ("Земля", "#c4a47c", 0, "земля", "earth", "Почва и камень — первостихия."),
    "air": ("Воздух", "#cee8ef", 0, "воздух", "air", "Ветер и небо — первостихия."),
    "steam": ("Пар", "#c4cfe5", 1, "воздух", "steam", "Вода, обращённая огнём в пар."),
    "stone": ("Камень", "#a6a6bb", 1, "земля", "stone", "Земля, обожжённая огнём в породу."),
    "clay": ("Глина", "#d2785f", 1, "земля", "clay", "Мокрая земля, годная для лепки."),
    "dust": ("Пыль", "#ddd0a2", 1, "воздух", "dust", "Земля, растёртая ветром в порошок."),
    "spark": ("Искра", "#ffe08a", 1, "огонь", "spark", "Маленький огонёк, готовый разгореться."),
    "mist": ("Туман", "#acc8e4", 1, "воздух", "mist", "Дымка из воды и воздуха."),
    "brick": ("Кирпич", "#a05242", 2, "земля", "brick", "Обожжённая глина — стройматериал."),
    "sand": ("Песок", "#f0d499", 2, "земля", "sand", "Камень, истёртый ветром в крупинки."),
    "plant": ("Росток", "#96d691", 2, "вода", "plant", "Первая жизнь, пробившаяся из глины."),
    "cloud": ("Облако", "#8cb0d0", 2, "воздух", "cloud", "Пар, собравшийся в небе тучей."),
    "ice": ("Лёд", "#a8e8ff", 3, "вода", "ice", "Вода, замёрзшая на вершине горы."),
    "mountain": ("Гора", "#877864", 2, "земля", "mountain", "Каменная громада."),
    "mud": ("Грязь", "#6e4628", 2, "земля", "mud", "Земля, размокшая в воде."),
    "metal": ("Металл", "#7896be", 2, "земля", "metal", "Руда, выбитая из камня искрой."),
    "life": ("Жизнь", "#4fd06f", 2, "вода", "life", "Искра, ожившая в воде."),
    "smoke": ("Дым", "#a0a3aa", 2, "воздух", "smoke", "Пыль, поднятая огнём в воздух."),
    "lava": ("Лава", "#f0561e", 2, "огонь", "lava", "Расплавленный огнём камень."),
    "glass": ("Стекло", "#93e2d3", 3, "земля", "glass", "Песок, сплавленный огнём в прозрачность."),
    "sky": ("Небо", "#64a8e8", 3, "воздух", "sky", "Высь над облаками."),
    "rain": ("Дождь", "#3f74c6", 3, "вода", "rain", "Вода, пролившаяся из тучи."),
    "storm": ("Гроза", "#47536b", 3, "воздух", "storm", "Туча, полная молний и грома."),
    "hail": ("Град", "#b9dcef", 4, "вода", "hail", "Ледяные зёрна, падающие из тучи."),
    "snow": ("Снег", "#f4fafd", 4, "вода", "snow", "Лёд, унесённый ветром в небо."),
    "volcano": ("Вулкан", "#8c422e", 3, "огонь", "volcano", "Гора, извергающая лаву."),
    "obsidian": ("Обсидиан", "#383248", 3, "земля", "obsidian", "Лава, застывшая в воде в стекло."),
    "magma": ("Магма", "#b23b2e", 3, "огонь", "magma", "Лава, копившаяся в толще земли."),
    "ash": ("Пепел", "#b4b8c0", 3, "земля", "ash", "Пепел — всё, что осталось от огня."),
    "gold": ("Золото", "#c69624", 3, "земля", "gold", "Металл, закалённый огнём — мечта алхимика."),
    "swamp": ("Болото", "#548036", 3, "вода", "swamp", "Грязь, заросшая растениями."),
    "fish": ("Рыба", "#40aac8", 3, "вода", "fish", "Жизнь, обжившая воду."),
    "bird": ("Птица", "#5d97d8", 3, "воздух", "bird", "Жизнь, поднявшаяся в воздух."),
    "beast": ("Зверь", "#a06a3c", 3, "земля", "beast", "Жизнь, ступившая на землю."),
    "person": ("Человек", "#eeaa8c", 3, "земля", "person", "Жизнь, слепленная из глины."),
    "seed": ("Семя", "#aa8246", 3, "земля", "seed", "Семя, уроненное ростком в пыль."),
    "grass": ("Трава", "#96d646", 3, "земля", "grass", "Росток, покрывший землю."),
    "mushroom": ("Гриб", "#b26d5f", 4, "земля", "mushroom", "Гриб, выросший на болоте."),
    "lightning": ("Молния", "#f5e13b", 4, "огонь", "lightning", "Разряд, бьющий из грозовой тучи."),
    "tornado": ("Смерч", "#8d939e", 4, "воздух", "tornado", "Вихрь из пыли и ветра."),
    "tool": ("Инструмент", "#77828c", 4, "земля", "tool", "Камень, приспособленный человеком."),
    "tree": ("Дерево", "#4e9150", 4, "земля", "tree", "Семя, проросшее в земле."),
    "sun": ("Солнце", "#ffd21f", 4, "огонь", "sun", "Огонь, зажжённый в небе."),
    "crystal": ("Кристалл", "#cbbdff", 4, "земля", "crystal", "Стекло, сложившееся в самоцвет."),
    "sandstorm": ("Песчаная буря", "#d4783c", 4, "воздух", "sandstorm", "Буря, несущая песок."),
    "forest": ("Лес", "#106e2d", 5, "земля", "forest", "Множество деревьев, ставшее лесом."),
    "wood": ("Древесина", "#d0a454", 5, "земля", "wood", "Древесина — материал из дерева."),
    "flower": ("Цветок", "#ef7fb4", 5, "земля", "flower", "Растение, расцветшее под солнцем."),
    "rainbow": ("Радуга", "#b96ad4", 5, "воздух", "rainbow", "Свет, преломлённый в дожде."),
    "desert": ("Пустыня", "#e2b666", 5, "земля", "desert", "Песок, иссушённый солнцем."),
    "boat": ("Лодка", "#965434", 6, "земля", "boat", "Древесина, поплывшая по воде."),
    "coal": ("Уголь", "#555860", 6, "земля", "coal", "Древесина, обожжённая без пламени."),
    "wall": ("Стена", "#b0664a", 3, "земля", "wall", "Кирпичи, сложенные в преграду."),
    "house": ("Дом", "#8a5a3a", 6, "земля", "house", "Стены под крышей — жилище."),
    "child": ("Ребёнок", "#f2c19a", 4, "земля", "child", "Новая жизнь, рождённая людьми."),
}

# [a, b, результат]
RECIPES = [
    ("fire", "water", "steam"),
    ("earth", "fire", "stone"),
    ("earth", "water", "clay"),
    ("air", "earth", "dust"),
    ("air", "fire", "spark"),
    ("air", "water", "mist"),
    ("clay", "fire", "brick"),
    ("clay", "water", "plant"),
    ("steam", "air", "cloud"),
    ("air", "stone", "sand"),
    ("mountain", "water", "ice"),
    ("stone", "earth", "mountain"),
    ("mist", "earth", "mud"),
    ("stone", "spark", "metal"),
    ("spark", "water", "life"),
    ("fire", "dust", "smoke"),
    ("stone", "fire", "lava"),
    ("fire", "sand", "glass"),
    ("cloud", "air", "sky"),
    ("cloud", "water", "rain"),
    ("cloud", "spark", "storm"),
    ("cloud", "ice", "hail"),
    ("ice", "air", "snow"),
    ("mountain", "fire", "volcano"),
    ("lava", "water", "obsidian"),
    ("lava", "earth", "magma"),
    ("fire", "plant", "ash"),
    ("metal", "fire", "gold"),
    ("mud", "plant", "swamp"),
    ("life", "water", "fish"),
    ("life", "air", "bird"),
    ("life", "earth", "beast"),
    ("life", "clay", "person"),
    ("plant", "dust", "seed"),
    ("earth", "plant", "grass"),
    ("storm", "spark", "lightning"),
    ("storm", "dust", "tornado"),
    ("person", "stone", "tool"),
    ("seed", "earth", "tree"),
    ("sky", "fire", "sun"),
    ("glass", "glass", "crystal"),
    ("sand", "storm", "sandstorm"),
    ("swamp", "plant", "mushroom"),
    ("tree", "plant", "forest"),
    ("tree", "stone", "wood"),
    ("sun", "plant", "flower"),
    ("rain", "sun", "rainbow"),
    ("sand", "sun", "desert"),
    ("wood", "water", "boat"),
    ("wood", "fire", "coal"),
    ("brick", "brick", "wall"),
    ("wall", "wood", "house"),
    ("person", "person", "child"),
]


def norm_name(s):
    """Нормализация имени для дедупликации: регистр, ё→е, лишние пробелы."""
    import re as _re
    s = str(s or "").strip().lower().replace("ё", "е")
    return _re.sub(r"\s+", " ", s)


# Теги природы веществ (v30, недельный слой). Словарь — тот же, что в gen_llm.TAGS.
TAG_BY_SLUG = {
    "air": "воздух", "ash": "земля", "beast": "зверь", "bird": "зверь",
    "boat": "трава", "brick": "камень", "child": "зверь", "clay": "земля",
    "cloud": "небо", "coal": "тьма", "crystal": "свет", "desert": "земля",
    "dust": "воздух", "earth": "земля", "fire": "огонь", "fish": "зверь",
    "flower": "трава", "forest": "трава", "glass": "свет", "gold": "металл",
    "grass": "трава", "hail": "лёд", "house": "камень", "ice": "лёд",
    "lava": "огонь", "life": "зверь", "lightning": "свет", "magma": "огонь",
    "metal": "металл", "mist": "вода", "mountain": "камень", "mud": "земля",
    "mushroom": "трава", "obsidian": "камень", "person": "зверь",
    "plant": "трава", "rain": "вода", "rainbow": "свет", "sand": "земля",
    "sandstorm": "воздух", "seed": "трава", "sky": "небо", "smoke": "тьма",
    "snow": "лёд", "spark": "огонь", "steam": "вода", "stone": "камень",
    "storm": "тьма", "sun": "свет", "swamp": "трава", "tool": "металл",
    "tornado": "воздух", "tree": "трава", "volcano": "огонь", "wall": "камень",
    "water": "вода", "wood": "трава",
}


def tag_for(slug, category):
    """Тег вещества: свой из карты, иначе категория (4 базовые входят в словарь)."""
    return TAG_BY_SLUG.get(slug, category or "")


def seed_db(conn):
    """Заполнить БД стартовым графом (идемпотентно)."""
    has_tag = any(r["name"] == "tag" for r in conn.execute("PRAGMA table_info(elements)").fetchall())
    for slug, (name, color, layer, cat, glyph, d) in ITEMS.items():
        if has_tag:
            conn.execute(
                "INSERT OR IGNORE INTO elements (slug, name, name_norm, color, layer, category, glyph, d, tag) VALUES (?,?,?,?,?,?,?,?,?)",
                (slug, name, norm_name(name), color, layer, cat, glyph, d, tag_for(slug, cat)),
            )
        else:
            conn.execute(
                "INSERT OR IGNORE INTO elements (slug, name, name_norm, color, layer, category, glyph, d) VALUES (?,?,?,?,?,?,?,?)",
                (slug, name, norm_name(name), color, layer, cat, glyph, d),
            )
    for a, b, out in RECIPES:
        a_row = conn.execute("SELECT id FROM elements WHERE slug = ?", (a,)).fetchone()
        b_row = conn.execute("SELECT id FROM elements WHERE slug = ?", (b,)).fetchone()
        out_row = conn.execute("SELECT id FROM elements WHERE slug = ?", (out,)).fetchone()
        if not (a_row and b_row and out_row):
            continue
        key = (a + "|" + b) if a <= b else (b + "|" + a)
        conn.execute(
            "INSERT OR IGNORE INTO recipes (pair_key, a, b, a_id, b_id, out_id) VALUES (?,?,?,?,?,?)",
            (key, a, b, a_row["id"], b_row["id"], out_row["id"]),
        )

# ---------------------------------------------------------------------------
# Боты: витрина рейтинга (v29, пункт 10). Живут в players с device_id bot-*,
# у каждого по 1 открытию (минимум, чтобы строка не была пустой) и случайный
# домик. Идемпотентно: повторный вызов ничего не дублирует и не отбирает
# открытия у настоящих игроков (UPDATE только по discoverer IS NULL).
# ---------------------------------------------------------------------------
import json as _json
import logging as _logging
import random as _random

_bot_log = _logging.getLogger("alchemists.seed")

BOT_NICKS = ["Боровик", "Кремень", "Луна", "Шёпот"]
BOT_CATS = ["window", "rug", "chair", "plant", "lamp", "table", "shelf", "bed", "fireplace"]
BOT_WALLS = ["#5a4d40", "#4d5a6b", "#6b4d5a", "#576b4d", "#6b5a4d"]
BOT_FLOORS = ["#5d452f", "#3f4d5d", "#5d3f4d", "#4d5d3f", "#54452f"]
BOT_AURAS = ["amber", "rose", "aqua", "violet"]


def _bot_house(rng: _random.Random) -> str:
    furn = {}
    for cat in BOT_CATS:
        n = rng.randint(0, 9)
        furn[cat] = cat if n == 0 else f"{cat}_{n}"
    return _json.dumps({
        "v": 1, "built": True,
        "theme": rng.choice(["cobalt", "ember", "moss", "violet"]),
        "aura": rng.choice(BOT_AURAS),
        "theme_custom": "", "aura_custom": "",
        "wall": rng.choice(BOT_WALLS), "floor": rng.choice(BOT_FLOORS),
        "furniture": furn,
    }, ensure_ascii=False)


def seed_bots(conn) -> None:
    """Вставить ботов рейтинга (идемпотентно). Вызывать после seed_db.

    С players.nick UNIQUE (T02) «INSERT OR IGNORE» молча пропускал бы бота,
    чей ник уже занят живым игроком, — пропуск стал явным и логируется.
    Поведение остального кода не меняется.
    """
    rng = _random.Random(20260912)
    for i, nick in enumerate(BOT_NICKS):
        device_id = f"bot-{i}"
        holder = conn.execute(
            "SELECT device_id FROM players WHERE nick = ?", (nick,)
        ).fetchone()
        holder_dev = None
        if holder is not None:
            holder_dev = holder["device_id"] if hasattr(holder, "keys") else holder[0]
        if holder is not None and holder_dev != device_id:
            _bot_log.warning(
                "seed_bots: бот '%s' (%s) пропущен: ник уже занят устройством '%s' "
                "(players.nick UNIQUE — INSERT OR IGNORE молча не вставил бы строку)",
                nick, device_id, holder_dev,
            )
            continue
        conn.execute(
            "INSERT OR IGNORE INTO players (nick, device_id, house) VALUES (?, ?, ?)",
            (nick, device_id, _bot_house(rng)),
        )
    # по 1 открытию каждому: первые рецепты по pair_key, только если ничьи
    rows = conn.execute(
        "SELECT pair_key FROM recipes ORDER BY pair_key LIMIT ?",
        (len(BOT_NICKS),),
    ).fetchall()
    for nick, r in zip(BOT_NICKS, rows):
        conn.execute(
            "UPDATE recipes SET discoverer = ? WHERE pair_key = ? AND discoverer IS NULL",
            (nick, r["pair_key"] if isinstance(r, dict) else r[0]),
        )
    conn.commit()
