-- Индекс под вторую ветку OR в каскаде удаления аккаунта:
--   DELETE FROM blocks WHERE blocker_device = ? OR blocked_device = ?
-- PK (blocker_device, blocked_device) левый префикс даёт только по
-- blocker_device, поэтому без индекса каждая зачистка — полный скан blocks.
-- EXPLAIN QUERY PLAN до/после: SCAN blocks → MULTI-INDEX OR.
--
-- DDL продублирован в schema.sql (тот же приём, что у 001_social.sql):
-- schema.sql для свежей БД, миграция для существующей. Файл идемпотентен.

CREATE INDEX IF NOT EXISTS ix_blocks_blocked ON blocks(blocked_device);
