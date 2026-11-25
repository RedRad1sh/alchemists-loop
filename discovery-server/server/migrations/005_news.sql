-- discovery-server/server/migrations/005_news.sql
-- «Алхимический вестник»: новости для клиента (GET /api/news/rss).
-- Конвенция 001/003: только DDL. Сид (7 внутриигровых новостей) живёт в
-- heal-шаге init_db (_seed_news, список _NEWS_SEED в server.py) — он
-- идемпотентен и срабатывает при пустой таблице на любой БД. На свежей БД
-- миграция создаёт таблицу, на живой БД VPS она — единственный способ
-- появиться; строка версии записывается раннером.

CREATE TABLE IF NOT EXISTS news_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    title        TEXT NOT NULL,
    body         TEXT NOT NULL DEFAULT '',
    tag          TEXT NOT NULL DEFAULT '',
    published_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_news_published ON news_items(published_at DESC);