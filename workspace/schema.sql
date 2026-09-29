PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS run_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hypotheses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL,
    title TEXT NOT NULL,
    rationale TEXT,
    attack_surface TEXT,
    expected_behavior TEXT,
    confidence REAL DEFAULT 0.5,
    parent_id INTEGER REFERENCES hypotheses(id)
);

CREATE TABLE IF NOT EXISTS experiments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TEXT,
    hypothesis_id INTEGER REFERENCES hypotheses(id),
    parent_experiment_id INTEGER REFERENCES experiments(id),
    status TEXT NOT NULL,
    purpose TEXT NOT NULL,
    procedure TEXT,
    build_variant TEXT,
    input_path TEXT,
    command TEXT,
    environment TEXT,
    exit_code INTEGER,
    signal TEXT,
    duration_ms INTEGER,
    stdout_path TEXT,
    stderr_path TEXT,
    artifact_path TEXT,
    result_summary TEXT
);

CREATE TABLE IF NOT EXISTS observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hypothesis_id INTEGER REFERENCES hypotheses(id),
    experiment_id INTEGER REFERENCES experiments(id),
    kind TEXT NOT NULL,
    summary TEXT NOT NULL,
    evidence_path TEXT,
    confidence REAL DEFAULT 1.0
);

CREATE TABLE IF NOT EXISTS conclusions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hypothesis_id INTEGER REFERENCES hypotheses(id),
    verdict TEXT NOT NULL,
    summary TEXT NOT NULL,
    security_impact TEXT,
    evidence TEXT,
    reproducibility TEXT,
    report_candidate INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS change_vectors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hypothesis_id INTEGER REFERENCES hypotheses(id),
    decision TEXT NOT NULL,
    evidence_refs_json TEXT NOT NULL,
    reason TEXT NOT NULL,
    next_action TEXT NOT NULL,
    alternatives_json TEXT NOT NULL DEFAULT '[]',
    session_id TEXT,
    idempotency_key TEXT UNIQUE
);

CREATE TABLE IF NOT EXISTS telemetry_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_type TEXT NOT NULL,
    session_id TEXT,
    turn_id TEXT,
    tool_use_id TEXT,
    agent_id TEXT,
    tool_name TEXT,
    outcome TEXT,
    input_bytes INTEGER,
    response_bytes INTEGER,
    dedupe_key TEXT UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_hypotheses_status ON hypotheses(status);
CREATE INDEX IF NOT EXISTS idx_experiments_hypothesis ON experiments(hypothesis_id);
CREATE INDEX IF NOT EXISTS idx_observations_hypothesis ON observations(hypothesis_id);
CREATE INDEX IF NOT EXISTS idx_observations_experiment ON observations(experiment_id);
CREATE INDEX IF NOT EXISTS idx_change_vectors_hypothesis ON change_vectors(hypothesis_id);
CREATE INDEX IF NOT EXISTS idx_telemetry_session ON telemetry_events(session_id, turn_id);
