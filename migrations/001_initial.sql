-- Remembro v2 database schema
-- Applied by sqlx::migrate!() on daemon startup

-- Commands table (primary store)
CREATE TABLE IF NOT EXISTS commands (
    id          TEXT PRIMARY KEY NOT NULL,           -- nanoid(12)
    name        TEXT NOT NULL UNIQUE,                 -- display name
    cmd         TEXT NOT NULL,                        -- the shell command
    category    TEXT NOT NULL DEFAULT 'general',      -- grouping category
    description TEXT,                                 -- human-readable description
    tags        TEXT,                                 -- JSON array of strings
    notes       TEXT,                                 -- free-text notes
    source      TEXT NOT NULL DEFAULT 'manual',       -- 'manual', 'shell', 'agent-opencode', 'agent-claude', 'pipe', 'migration-v1'
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    hit_count   INTEGER NOT NULL DEFAULT 0,          -- times this command was retrieved
    last_used   TEXT                                  -- last retrieval timestamp
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_commands_category ON commands(category);
CREATE INDEX IF NOT EXISTS idx_commands_name ON commands(name);
CREATE INDEX IF NOT EXISTS idx_commands_source ON commands(source);
CREATE INDEX IF NOT EXISTS idx_commands_created ON commands(created_at);

-- Full-text search index (FTS5)
CREATE VIRTUAL TABLE IF NOT EXISTS commands_fts USING fts5(
    name,
    cmd,
    description,
    notes,
    tags,
    content='commands',
    content_rowid='rowid',
    tokenize='porter unicode61'
);

-- Triggers to keep FTS index in sync
CREATE TRIGGER IF NOT EXISTS commands_ai AFTER INSERT ON commands BEGIN
    INSERT INTO commands_fts(rowid, name, cmd, description, notes, tags)
    VALUES (new.rowid, new.name, new.cmd, new.description, new.notes, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS commands_ad AFTER DELETE ON commands BEGIN
    INSERT INTO commands_fts(commands_fts, rowid, name, cmd, description, notes, tags)
    VALUES ('delete', old.rowid, old.name, old.cmd, old.description, old.notes, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS commands_au AFTER UPDATE ON commands BEGIN
    INSERT INTO commands_fts(commands_fts, rowid, name, cmd, description, notes, tags)
    VALUES ('delete', old.rowid, old.name, old.cmd, old.description, old.notes, old.tags);
    INSERT INTO commands_fts(rowid, name, cmd, description, notes, tags)
    VALUES (new.rowid, new.name, new.cmd, new.description, new.notes, new.tags);
END;

-- Auto-bump updated_at on any update
CREATE TRIGGER IF NOT EXISTS commands_bump_updated AFTER UPDATE ON commands
WHEN old.updated_at IS NOT new.updated_at OR old.updated_at IS new.updated_at
BEGIN
    UPDATE commands SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = new.id;
END;

-- Capture log (append-only event log)
CREATE TABLE IF NOT EXISTS capture_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    source      TEXT NOT NULL,
    cmd         TEXT NOT NULL,
    context     TEXT,                                -- optional JSON context (cwd, exit code, etc.)
    captured_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_capture_log_source ON capture_log(source);
CREATE INDEX IF NOT EXISTS idx_capture_log_captured ON capture_log(captured_at);