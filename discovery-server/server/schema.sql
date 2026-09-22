-- Схема БД сервера первооткрытий
-- SQLite, запускается через PRAGMA journal_mode=WAL
-- Стартовые данные (54 вещества / 50 рецептов) загружаются из seed.py.

PRAGMA journal_mode=WAL;

-- Все элементы (включая сгенерированные)
CREATE TABLE IF NOT EXISTS elements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    name_norm TEXT,
    color TEXT NOT NULL,
    layer INTEGER NOT NULL,
    category TEXT NOT NULL,
    glyph TEXT NOT NULL DEFAULT '',
    d TEXT NOT NULL DEFAULT '',
    author TEXT,
    -- device_id автора (T02): экономически значимые связи (резонанс, export,
    -- delete) ключуются по нему; author/nick — только витрина. Для старых строк
    -- заполняется backfill-ом в init_db(); NULL без backfill — fallback по nick.
    author_device TEXT,
    resonance_count INTEGER NOT NULL DEFAULT 0,
    tag TEXT NOT NULL DEFAULT '',
    created_at TEXT DEFAULT (datetime('now'))
);

-- Рецепты (pair_key = нормализованный ключ пары)
CREATE TABLE IF NOT EXISTS recipes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pair_key TEXT NOT NULL UNIQUE,
    a TEXT NOT NULL,
    b TEXT NOT NULL,
    a_id INTEGER REFERENCES elements(id),
    b_id INTEGER REFERENCES elements(id),
    out_id INTEGER NOT NULL REFERENCES elements(id),
    discoverer TEXT,
    -- первооткрыватель по device_id (T02) — см. elements.author_device
    discoverer_device TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Игроки
-- nick без UNIQUE в DDL: уникальность наводит миграция init_db() (идемпотентно:
-- разрешение коллизий + CREATE UNIQUE INDEX), чтобы старые БД не падали на
-- «duplicate key» при первом старте после деплоя.
CREATE TABLE IF NOT EXISTS players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nick TEXT NOT NULL,
    device_id TEXT NOT NULL UNIQUE,
    house TEXT,
    house_updated_at TEXT,
    last_seen TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Отголоски резонанса (v24): незабранные повторы чужих веществ + вечный счётчик.
-- balance капается (ECHO_CAP), total бесконечен (вехи 10/50/100). last_apprentice_day —
-- день последнего гранта «подмастерьев гильдии» (fallback малой аудитории).
CREATE TABLE IF NOT EXISTS echoes (
    device_id TEXT NOT NULL PRIMARY KEY,
    balance INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 0,
    last_apprentice_day TEXT
);

-- Письма Светика (v27): ежедневная загадка-пара. Конверты-недоделки хранятся
-- (до 7 шт.), решённые копят вечный счётчик (каждое 5-е → +кап на клиенте).
CREATE TABLE IF NOT EXISTS letters (
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
);

-- Очередь блокировок для race-condition
CREATE TABLE IF NOT EXISTS pending_pairs (
    pair_key TEXT NOT NULL PRIMARY KEY,
    state TEXT NOT NULL DEFAULT 'pending',
    lock_ts REAL NOT NULL DEFAULT (strftime('%s','now')),
    owner TEXT,
    attempted_by TEXT
);

-- Пары, признанные несочетаемыми («туман рассеялся», элемент не создаётся)
CREATE TABLE IF NOT EXISTS rejected_pairs (
    pair_key TEXT NOT NULL PRIMARY KEY,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Лента событий мира: последние первооткрытия (для «живой ленты» в игре)
CREATE TABLE IF NOT EXISTS world_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pair_key TEXT NOT NULL,
    a TEXT NOT NULL,
    b TEXT NOT NULL,
    out TEXT NOT NULL,
    out_name TEXT NOT NULL,
    discoverer TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Ежедневная цель: целевой ингредиент дня. Каждый игрок выполняет её лично,
-- «победитель» больше не закрывает день (иначе при 1000 игроков гонка
-- заканчивается за секунды). first_nick — кто справился первым (для ленты).
CREATE TABLE IF NOT EXISTS challenges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day TEXT NOT NULL UNIQUE,
    target TEXT NOT NULL,
    target_name TEXT NOT NULL,
    hint TEXT NOT NULL,
    first_nick TEXT,
    first_device TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    closed_at TEXT
);

-- Личный счёт в ежедневной цели: по очку за каждое новое вещество из цели дня.
CREATE TABLE IF NOT EXISTS challenge_scores (
    day TEXT NOT NULL,
    device_id TEXT NOT NULL,
    nick TEXT NOT NULL,
    points INTEGER NOT NULL DEFAULT 0,
    first_at TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (day, device_id)
);

-- Индексы для производительности
-- idx_elements_name_norm создаётся в init_db() ПОСЛЕ миграции колонки name_norm:
-- на старых БД колонки ещё нет, и создание индекса здесь упало бы
-- с «no such column: name_norm».
CREATE INDEX IF NOT EXISTS idx_elements_slug ON elements(slug);
CREATE INDEX IF NOT EXISTS idx_elements_category ON elements(category);
CREATE INDEX IF NOT EXISTS idx_elements_layer ON elements(layer);
CREATE INDEX IF NOT EXISTS idx_recipes_pair_key ON recipes(pair_key);
CREATE INDEX IF NOT EXISTS idx_recipes_discoverer ON recipes(discoverer);
CREATE INDEX IF NOT EXISTS idx_recipes_out_id ON recipes(out_id);
CREATE INDEX IF NOT EXISTS idx_recipes_a_id ON recipes(a_id);
CREATE INDEX IF NOT EXISTS idx_recipes_b_id ON recipes(b_id);
CREATE INDEX IF NOT EXISTS idx_elements_author ON elements(author);
CREATE INDEX IF NOT EXISTS idx_players_device_id ON players(device_id);
CREATE INDEX IF NOT EXISTS idx_players_nick ON players(nick);
CREATE INDEX IF NOT EXISTS idx_pending_pairs_state ON pending_pairs(state);
CREATE INDEX IF NOT EXISTS idx_pending_pairs_lock_ts ON pending_pairs(lock_ts);
CREATE INDEX IF NOT EXISTS idx_world_events_created ON world_events(created_at);
CREATE INDEX IF NOT EXISTS idx_challenges_day ON challenges(day);

-- Страница Атласа: одна общемировая загадка-пары в день (v28)
CREATE TABLE IF NOT EXISTS atlas_pages (
    day TEXT PRIMARY KEY,
    a TEXT NOT NULL,
    b TEXT NOT NULL,
    a_name TEXT NOT NULL,
    b_name TEXT NOT NULL,
    riddle TEXT NOT NULL DEFAULT '',
    created_at TEXT DEFAULT (datetime('now'))
);
-- Кто какие страницы разгадал (веха: каждые 10 → +кап на клиенте)
CREATE TABLE IF NOT EXISTS atlas_solves (
    device_id TEXT NOT NULL,
    day TEXT NOT NULL,
    PRIMARY KEY (device_id, day)
);
CREATE INDEX IF NOT EXISTS idx_atlas_solves_device ON atlas_solves(device_id);

-- Недельный слой (v30): ярмарка гильдии + туманная жила
-- Котёл недели: общий тег-цель, цель котла, живой прогресс (вклады игроков).
-- Подмастерья (+10% цели в день) считаются на чтении, в БД не пишутся.
CREATE TABLE IF NOT EXISTS fair_weeks (
    week TEXT PRIMARY KEY,
    tag TEXT NOT NULL,
    goal INTEGER NOT NULL,
    progress INTEGER NOT NULL DEFAULT 0
);
-- Учённые пары недели (антифлуд: одна пара — один вклад с устройства в неделю)
CREATE TABLE IF NOT EXISTS fair_pairs (
    week TEXT NOT NULL,
    device_id TEXT NOT NULL,
    pair_key TEXT NOT NULL,
    PRIMARY KEY (week, device_id, pair_key)
);
-- Личные вклады в котёл недели
CREATE TABLE IF NOT EXISTS fair_contrib (
    week TEXT NOT NULL,
    device_id TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (week, device_id)
);
-- Забранные награды котла (неделя закрыта для устройства)
CREATE TABLE IF NOT EXISTS fair_claims (
    week TEXT NOT NULL,
    device_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    PRIMARY KEY (week, device_id)
);
-- Находки устройства в жиле недели (счётчик + прожилки с капом 5/неделю)
CREATE TABLE IF NOT EXISTS vein_hits (
    week TEXT NOT NULL,
    device_id TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    streaks INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (week, device_id)
);
