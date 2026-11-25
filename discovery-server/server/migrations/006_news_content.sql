-- discovery-server/server/migrations/006_news_content.sql
-- «Алхимический вестник»: полная статья (Markdown) и картинки статей.
-- Только DDL (конвенция 001/003/005). body_md — полный текст статьи для
-- content:encoded в RSS; body остаётся кратким описанием (description).
-- news_images хранит загруженные картинки (BLOB) под ссылки
-- ![alt](/api/news/images/N) из markdown. Сид — в heal (_seed_news).

ALTER TABLE news_items ADD COLUMN body_md TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS news_images (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    news_id    INTEGER NOT NULL,
    mime       TEXT NOT NULL,
    data       BLOB NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_news_images_news ON news_images(news_id);