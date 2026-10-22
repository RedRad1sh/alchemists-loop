-- discovery-server/server/migrations/004_trade_items.sql
-- NM §2.1: позиции оффера переезжают из одиночных колонок trade_orders в
-- таблицу trade_items (N↔M). DDL продублирован в schema.sql (конвенция
-- 001/002/003): на свежей БД схема уже полная, и эта миграция проходит
-- вхолостую (IF NOT EXISTS), записывая только строку версии; на живой БД VPS
-- она — единственный способ таблице появиться.
--
-- Heal старых строк (INSERT…SELECT из give_*/want_*) и четыре DROP COLUMN здесь
-- НЕ живут — причина и детали: docstring `_migrate_trade_items` в server.py.

CREATE TABLE IF NOT EXISTS trade_items (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id  INTEGER NOT NULL REFERENCES trade_orders(id) ON DELETE CASCADE,
    side      TEXT NOT NULL CHECK (side IN ('give', 'want')),
    card_id   TEXT NOT NULL DEFAULT '',
    craft_id  TEXT NOT NULL DEFAULT '',
    pos       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_trade_items_order ON trade_items(order_id, side);
