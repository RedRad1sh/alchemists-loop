-- Персональные target-записи Experiment и идемпотентный журнал попыток.
CREATE TABLE IF NOT EXISTS personal_experiment_targets (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    cycle_week TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('world', 'llm')),
    target_slug TEXT,
    target_name TEXT NOT NULL,
    target_name_norm TEXT NOT NULL,
    target_hint TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'waiting_next_slot', 'conflict')),
    attempts INTEGER NOT NULL DEFAULT 0,
    successful_steps INTEGER NOT NULL DEFAULT 0,
    spent_ether INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    completed_at TEXT,
    completed_request_id TEXT,
    next_eligible_week TEXT,
    version INTEGER NOT NULL DEFAULT 1,
    UNIQUE (device_id, sequence),
    UNIQUE (device_id, cycle_week)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_personal_experiment_one_active
    ON personal_experiment_targets(device_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS personal_experiment_attempts (
    target_id TEXT NOT NULL REFERENCES personal_experiment_targets(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    pair_key TEXT NOT NULL,
    status TEXT NOT NULL,
    result_slug TEXT,
    ether_charged INTEGER NOT NULL DEFAULT 0,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (target_id, request_id)
);

CREATE INDEX IF NOT EXISTS idx_personal_experiment_attempts_device
    ON personal_experiment_attempts(device_id, target_id);
