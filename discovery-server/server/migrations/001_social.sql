-- S1 «Друзья и переписка»: пять таблиц социального слоя.
--
-- Файл идемпотентен (IF NOT EXISTS) и продублирован в конце schema.sql —
-- тот же приём, что у vein_points/sigil_*: schema.sql создаёт таблицы для
-- свежей БД, миграция — для существующей. Совпадение формы держит
-- tests/test_social.py::TestSchema::test_migration_file_alone_creates_same_shape.
--
-- Ключ всего — device_id, ник только витрина: ник сменяем через POST /api/me,
-- поэтому любой граф по нику рвётся при переименовании. Единственное место,
-- где ник входит в систему, — target_nick в POST /api/friend/request.

CREATE TABLE IF NOT EXISTS friend_edges (
    pair_key TEXT NOT NULL PRIMARY KEY,
    a_device TEXT NOT NULL,
    b_device TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    requester_device TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_friend_edges_a ON friend_edges(a_device, state);
CREATE INDEX IF NOT EXISTS ix_friend_edges_b ON friend_edges(b_device, state);

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pair_key TEXT NOT NULL,
    from_device TEXT NOT NULL,
    body TEXT NOT NULL,
    sent_at TEXT NOT NULL,
    read_at TEXT
);
CREATE INDEX IF NOT EXISTS ix_messages_pair ON messages(pair_key, id);
CREATE INDEX IF NOT EXISTS ix_messages_from ON messages(from_device, sent_at);
CREATE INDEX IF NOT EXISTS ix_messages_sent ON messages(sent_at);

CREATE TABLE IF NOT EXISTS blocks (
    blocker_device TEXT NOT NULL,
    blocked_device TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (blocker_device, blocked_device)
);

CREATE TABLE IF NOT EXISTS spirit_messages (
    device_id TEXT NOT NULL,
    day TEXT NOT NULL,
    trigger_id TEXT NOT NULL,
    body TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'template',
    message_id INTEGER NOT NULL DEFAULT 0,
    generated_at TEXT NOT NULL,
    PRIMARY KEY (device_id, day)
);

-- last_inbox_day нужен вместо players.last_seen для триггера «return»:
-- last_seen обновляет _upsert_player на любом POST /api/me, а клиент зовёт
-- /api/me в стартовом обмене РАНЬШЕ inbox — триггер не сработал бы ни разу.
CREATE TABLE IF NOT EXISTS social_state (
    device_id TEXT NOT NULL PRIMARY KEY,
    last_inbox_day TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
