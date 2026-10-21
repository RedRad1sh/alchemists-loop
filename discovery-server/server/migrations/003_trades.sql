-- discovery-server/server/migrations/003_trades.sql
-- S2: таблицы обмена. DDL продублирован в schema.sql (конвенция 001/002):
-- на свежей БД схема уже полная, и эта миграция проходит вхолостую
-- (IF NOT EXISTS), записывая только строку версии; на живой БД VPS она —
-- единственный способ появиться.

-- S2 обмен картами. trade_orders — НАМЕРЕНИЕ, а не факт владения: единственный
-- источник факта — sigil_crafts, поэтому copies нельзя накрутить торговлей.
-- Ни резерва, ни счётчиков копий здесь нет намеренно (спека §3, §5.2).
CREATE TABLE IF NOT EXISTS trade_orders (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    maker_device      TEXT NOT NULL,
    taker_device      TEXT NOT NULL,
    give_card_id      TEXT NOT NULL DEFAULT '',
    give_craft_id     TEXT NOT NULL DEFAULT '',
    want_card_id      TEXT NOT NULL DEFAULT '',
    want_craft_id     TEXT NOT NULL DEFAULT '',
    state             TEXT NOT NULL DEFAULT 'pending',
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL
);
-- Оба среза list-а — «чей ящик + state», поэтому индекс с state вторым столбцом.
CREATE INDEX IF NOT EXISTS ix_trade_taker ON trade_orders(taker_device, state);
CREATE INDEX IF NOT EXISTS ix_trade_maker ON trade_orders(maker_device, state);

-- Недельный счётчик «свершившихся переносов» (TRADE_WEEK_LIMIT). Ключ — ISO-
-- неделя 'YYYY-Www' (_week_key), поэтому сброс лимита не требует уборки.
CREATE TABLE IF NOT EXISTS trade_counts (
    week      TEXT NOT NULL,
    device_id TEXT NOT NULL,
    count     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (week, device_id)
);
