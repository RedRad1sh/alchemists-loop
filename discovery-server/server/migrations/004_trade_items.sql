-- discovery-server/server/migrations/004_trade_items.sql
-- NM §2.1: позиции оффера переезжают из одиночных колонок trade_orders в
-- таблицу trade_items (N↔M). DDL продублирован в schema.sql (конвенция
-- 001/002/003): на свежей БД схема уже полная, и эта миграция проходит
-- вхолостую (IF NOT EXISTS), записывая только строку версии; на живой БД VPS
-- она — единственный способ таблице появиться.
--
-- Heal старых строк (INSERT…SELECT из give_*/want_*) и четыре DROP COLUMN
-- ЗДЕСЬ НЕ живут: init_db сначала исполняет schema.sql (уже без колонок), а
-- затем применяет этот файл даже на свежей БД (версия 4 ещё не записана) —
-- SELECT по несуществующей колонке ронял бы каждый прогон. Переезд данных
-- делает Python-шаг _migrate_trade_items под PRAGMA table_info(trade_orders)
-- — та же конвенция heal'ов, что glyph/house/first_nick в init_db; он
-- идемпотентен: после DROP guard ложен.

CREATE TABLE IF NOT EXISTS trade_items (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id  INTEGER NOT NULL REFERENCES trade_orders(id) ON DELETE CASCADE,
    side      TEXT NOT NULL CHECK (side IN ('give', 'want')),
    card_id   TEXT NOT NULL DEFAULT '',
    craft_id  TEXT NOT NULL DEFAULT '',
    pos       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_trade_items_order ON trade_items(order_id, side);
