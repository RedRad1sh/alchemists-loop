CREATE TABLE personal_experiment_allocations (
    device_id TEXT PRIMARY KEY,
    sequence INTEGER NOT NULL,
    claim_token TEXT NOT NULL,
    claimed_at REAL NOT NULL
);
