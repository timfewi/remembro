# Remembro v2 — Architecture & Deployment Design

## Overview

Remembro v2 evolves from a 177-line Bash CLI to a **terminal daemon** (`rembrodd`)
with Unix-socket IPC, fast vector search, agent-output watching, and NixOS-native
deployment. The CLI client (`rbro`) becomes a thin socket client while the daemon
handles storage, indexing, and real-time capture.

```
┌──────────────────────────────────────────────────┐
│                  User Terminal                     │
│                                                    │
│  $ rbro -l            ┌──────────────────┐        │
│  $ rbro !<query>      │   rembrodd        │        │
│  $ rbro --add ...     │   (daemon)        │        │
│                       │                   │        │
│  ┌──────────┐  Unix   │  ┌─────────────┐  │        │
│  │  rbro CLI │◄──────►│  │ Socket I/O  │  │        │
│  └──────────┘  socket │  └──────┬──────┘  │        │
│                       │         │         │        │
│  ┌──────────┐         │  ┌──────┴──────┐  │        │
│  │ .zshrc   │──────►  │  │ Vector      │  │        │
│  │ preexec  │  FIFO   │  │ Index       │  │        │
│  └──────────┘  or     │  │ (Embedding) │  │        │
│                socket │  └──────┬──────┘  │        │
│                       │         │         │        │
│  ┌──────────┐         │  ┌──────┴──────┐  │        │
│  │ Agent    │──────►  │  │ SQLite      │  │        │
│  │ Output   │  pipe   │  │ Store       │  │        │
│  └──────────┘         │  └─────────────┘  │        │
│                       └──────────────────┘        │
└──────────────────────────────────────────────────┘
```

## 1. Architecture

### 1.1 Process Model

| Component | Binary          | Type               | Description                                       |
| --------- | --------------- | ------------------ | ------------------------------------------------- |
| Daemon    | `rembrodd`      | background service | Owns all state, listens on Unix socket            |
| CLI       | `rbro`          | foreground process | Thin client — sends JSON-RPC over socket          |
| Init      | `remembro init` | one-shot           | First-run setup (download model, create DB, seed) |

### 1.2 Communication Protocol

**Transport:** Unix domain socket at `$XDG_RUNTIME_DIR/remembro/rembro.sock`
(fallback: `~/.remembro/rembro.sock`)

**Protocol:** JSON-RPC 2.0 over newline-delimited streams

```json
// Request
{"jsonrpc":"2.0","id":1,"method":"search","params":{"query":"docker build","limit":5}}

// Response
{"jsonrpc":"2.0","id":1,"result":[{"name":"docker-build","cmd":"docker build -t myapp .","score":0.92}]}
```

**Methods:**

| Method    | Params                                 | Returns                         | Description                          |
| --------- | -------------------------------------- | ------------------------------- | ------------------------------------ |
| `ping`    | `{}`                                   | `"pong"`                        | Health check                         |
| `search`  | `{query, limit?, threshold?}`          | `[Entry]`                       | Vector + keyword search              |
| `list`    | `{category?, limit?}`                  | `[Entry]`                       | List stored commands                 |
| `add`     | `{name, cmd, category?, tags?, desc?}` | `{id}`                          | Insert new entry                     |
| `delete`  | `{name}`                               | `{ok: true}`                    | Remove entry                         |
| `capture` | `{source, cmd, context?}`              | `{id}`                          | Agent/shell push a command           |
| `status`  | `{}`                                   | `{db_size, index_size, uptime}` | Daemon stats                         |
| `tail`    | `{lines?}`                             | `[LogEntry]`                    | Recent capture log                   |
| `watch`   | `{}`                                   | stream                          | Real-time capture stream (SSE-style) |

### 1.3 Data Storage

**Primary DB:** `~/.remembro/store.db` (SQLite via `sqlx`)

```sql
CREATE TABLE commands (
    id          TEXT PRIMARY KEY,      -- nanoid(12)
    name        TEXT NOT NULL UNIQUE,
    cmd         TEXT NOT NULL,
    category    TEXT NOT NULL DEFAULT 'general',
    description TEXT,
    tags        TEXT,                   -- JSON array
    notes       TEXT,
    source      TEXT,                   -- 'manual', 'agent-opencode', 'agent-claude', 'shell', 'migration-v1'
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    hit_count   INTEGER NOT NULL DEFAULT 0,
    last_used   TEXT
);

CREATE VIRTUAL TABLE commands_fts USING fts5(
    name, cmd, description, notes, tags,
    content='commands', content_rowid='rowid'
);

CREATE INDEX idx_commands_category ON commands(category);
CREATE INDEX idx_commands_name ON commands(name);
CREATE INDEX idx_commands_source ON commands(source);
```

**Vector Index:** `~/.remembro/index/` — HNSW index file + embedding cache.

The daemon loads embeddings at startup. For the first iteration, use a small
local ONNX model (e.g., `all-MiniLM-L6-v2` via `ort` crate) to keep it
self-contained. Fallback: keyword-only (FTS5) if model not downloaded.

### 1.4 Logging

**Log file:** `~/.remembro/logs/rembrodd.jsonl` (rotated)

```jsonl
{"ts":"2026-05-26T10:00:00Z","level":"info","msg":"daemon started","pid":1234}
{"ts":"2026-05-26T10:00:01Z","level":"info","msg":"socket listening","path":"/run/user/1000/remembro/rembro.sock"}
{"ts":"2026-05-26T10:01:00Z","level":"info","msg":"captured command","source":"preexec","cmd":"docker compose up"}
{"ts":"2026-05-26T10:02:00Z","level":"warn","msg":"search query returned 0 results","query":"unknown thing"}
```

Stderr goes to **journald** (when run as systemd service) or terminal stderr.

## 2. Deployment

### 2.1 NixOS Module (`nix/remembro-nixos-module.nix`)

Provides `services.remembro` with systemd service, socket activation, and
user/group management.

```nix
# Example usage in configuration.nix:
{
  imports = [ inputs.remembro.nixosModules.default ];

  services.remembro = {
    enable = true;
    user = "tim";
    group = "users";
    vectorSearch = {
      enable = true;
      model = "all-MiniLM-L6-v2";  # or null for FTS5-only
    };
    capture = {
      shellHooks = true;    # Enable .zshrc hook injection
      agentSocket = true;   # Listen on generic agent FIFO
    };
    log = {
      level = "info";
      maxFiles = 7;
      maxSize = "10M";
    };
  };
}
```

### 2.2 Systemd Service

The daemon runs as a **user service** (`systemd --user`) so it follows the
user's session lifecycle. Socket activation ensures the socket exists even
before the daemon starts.

**Unit: `rembrodd.service`** (generated by NixOS module)

```ini
[Unit]
Description=Remembro daemon — terminal command memory
Documentation=https://github.com/timfewi/remembro
After=network.target

[Service]
Type=notify
ExecStart=@out@/bin/rembrodd
Restart=on-failure
RestartSec=5
NotifyAccess=main

# Security
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.remembro
NoNewPrivileges=true

# Resource limits
CPUQuota=50%
MemoryMax=256M
IOReadBandwidthMax=/dev/null 5M

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**Socket: `rembrodd.socket`**

```ini
[Unit]
Description=Remembro daemon socket

[Socket]
ListenStream=%t/remembro/rembro.sock
SocketMode=0600
DirectoryMode=0700
RemoveOnStop=true

[Install]
WantedBy=sockets.target
```

**Agent capture FIFO** — additional socket for agent push:

```ini
# remembro-capture.socket (separate, or same socket with different endpoint)
ListenStream=%t/remembro/capture.sock
SocketMode=0666
```

### 2.3 Home-Manager Integration (`nix/remembro-home-manager.nix`)

Injects shell hooks and ensures the daemon is running.

```nix
{ config, pkgs, ... }: {
  home.packages = [ pkgs.remembro ];

  systemd.user.services.rembrodd = {
    Unit = {
      Description = "Remembro daemon";
      After = [ "sockets.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = "${pkgs.remembro}/bin/rembrodd";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };

  programs.zsh.initExtra = ''
    # remembro shell hooks
    if command -v remembro-hook &>/dev/null; then
      eval "$(remembro-hook init zsh)"
    fi
  '';
}
```

### 2.4 Shell Hooks (`shell-integration.sh`)

Shipped as `remembro-hook` binary/script. Installed into `.zshrc` via:

```bash
# Add to .zshrc
eval "$(remembro-hook init zsh)"

# Generated hook code:
__remembro_preexec() {
    # Send command to daemon via capture socket
    # Rate-limited: skip if last send < 500ms ago
    # Skipped for very short cmds (< 3 chars) or common no-ops (ls, cd, pwd)
    local cmd="$1"
    [[ ${#cmd} -lt 3 ]] && return
    [[ "$cmd" == "ls" || "$cmd" == "cd" || "$cmd" == "pwd" || "$cmd" == "clear" ]] && return
    echo "{\"method\":\"capture\",\"params\":{\"source\":\"shell\",\"cmd\":\"$cmd\"}}" \
        | nc -U -w1 "$XDG_RUNTIME_DIR/remembro/capture.sock" 2>/dev/null
}

__remembro_precmd() {
    # Could track exit codes or duration in future
    :
}

preexec_functions+=(__remembro_preexec)
precmd_functions+=(__remembro_precmd)
```

### 2.5 Kitty Terminal Integration

Kitty integration happens at the **shell level** (not kitty-specific IPC).
However, remembro can leverage kitty's `--detach` for opening panes:

```bash
# Open a command from remembro in a new kitty pane
rbro --run docker-compose-up-build
# → kitty @ launch --type=tab --cwd current docker compose up --build
```

The daemon can watch kitty's `~/.local/share/kitty/terminal-*` log if
`shell_integration enabled` is set in kitty.conf, capturing commands
from all kitty panes via the shared shell hook.

Kitty config hint (documented, not auto-injected):

```ini
# ~/.config/kitty/kitty.conf
shell_integration enabled
```

### 2.6 First-Run Initialization

```bash
# One-time setup
remembro init

# What it does:
# 1. Creates ~/.remembro/ directory structure
# 2. Initializes SQLite DB with schema
# 3. Downloads embedding model (if vector search enabled)
#    → ~/.remembro/model/all-MiniLM-L6-v2.onnx
# 4. Seeds data from bundled seed-data.json (if exists)
# 5. Starts daemon (systemctl --user start rembrodd)
# 6. Optionally hooks into shell (prompt to add to .zshrc)
```

### 2.7 Upgrade Path from v1

```bash
# Automatic migration on first `remembro init` with v1 data present
# Detects: ~/.remembro/data.json exists
# Runs: remembro migrate

# Manual migration:
remembro migrate --from ~/.remembro/data.json

# What it does:
# 1. Reads v1 data.json
# 2. For each command entry, adds source="migration-v1"
# 3. Validates and imports into SQLite
# 4. Backs up old data.json → data.json.v1-bak
# 5. Generates migration report
```

## 3. Monitoring & Logging

### 3.1 Health Checks

```bash
# Quick check — is daemon running?
rembrodd status
# → rembrodd: running (pid 1234, uptime 3h 12m, 42 commands indexed)

# Socket check
echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' \
    | nc -U "$XDG_RUNTIME_DIR/remembro/rembro.sock"

# Systemd check
systemctl --user status rembrodd

# Watchdog (for monitoring scripts)
systemctl --user is-active rembrodd
```

### 3.2 Log Rotation

Managed by systemd's built-in journald log rotation + daemon-side JSONL rotation.

```nix
# NixOS module log rotation config:
services.remembro = {
  log = {
    enable = true;        # Enable JSONL logging alongside journald
    path = "%h/.remembro/logs/rembrodd.jsonl";
    maxSize = "10M";      # Rotate at 10 MB
    maxFiles = 7;         # Keep 7 rotated files
    compress = true;      # Gzip old logs
  };
};
```

The daemon handles rotation internally with `rolling-file` (Rust crate) or
defers to `logrotate`:

```bash
# /etc/logrotate.d/remembro (standalone install)
/home/tim/.remembro/logs/rembrodd.jsonl {
    daily
    rotate 7
    size 10M
    compress
    notifempty
    missingok
    postrotate
        systemctl --user kill -s USR1 rembrodd
    endscript
}
```

### 3.3 Error Reporting

| Channel                   | What goes there                     | When                     |
| ------------------------- | ----------------------------------- | ------------------------ |
| **journald**              | All stderr output, panic messages   | Always (systemd-managed) |
| **JSONL log**             | Structured logs (info, warn, error) | If `log.enable = true`   |
| **Socket error response** | JSON-RPC error object               | Per-request failures     |

Error format in journald:

```
May 26 10:00:05 host rembrodd[1234]: ERROR [capture] failed to connect to socket: Connection refused
```

Error format in JSONL:

```jsonl
{
  "ts": "2026-05-26T10:00:05Z",
  "level": "error",
  "msg": "capture failed",
  "source": "shell",
  "error": "connection refused",
  "retry_in": 5
}
```

Panic hook reports to both journald and JSONL before aborting.

### 3.4 Resource Usage

Built-in `rembrodd status` exposes resource metrics:

```bash
$ rembrodd status
{
  "pid": 1234,
  "uptime_sec": 11520,
  "memory_kb": 24576,
  "cpu_pct": 0.3,
  "db_size_kb": 128,
  "index_size_kb": 4096,
  "commands_total": 142,
  "captures_total": 3891,
  "searches_total": 245,
  "socket_connections": 1
}
```

Monitoring via `systemd` resource tracking:

```bash
# Peak memory
systemctl --user show rembrodd -P MemoryMax
# Current memory
systemctl --user show rembrodd -P MemoryCurrent
# CPU usage
systemctl --user show rembrodd -P CPUUsageNSec
```

Recommended alerting thresholds:

- Memory > 200 MB → warn (leak suspected)
- CPU > 20% sustained → warn (index rebuild or hot loop)
- Daemon restart > 3×/hour → critical (crash loop)

## 4. Agent Integration

### 4.1 OpenCode Hook

OpenCode can push commands to remembro via its post-tool hook or a custom MCP server.

**Option A: OpenCode post-exec hook (recommended)**

In `.opencode/config.json` or `opencode.json`:

```json
{
  "hooks": {
    "postTool": {
      "command": "remembro-capture",
      "args": ["--source", "opencode", "--cmd", "{tool.output}"]
    }
  }
}
```

**Option B: Dedicated MCP server**

Shipped as `remembro-mcp` — an MCP server that wraps the daemon socket:

```json
{
  "mcpServers": {
    "remembro": {
      "command": "remembro-mcp",
      "args": []
    }
  }
}
```

The MCP server exposes two tools:

- `remember_command(name, cmd, category?, tags?, description?)` — explicitly store
- `search_commands(query, limit?, threshold?)` — Vector search existing DB

### 4.2 Claude Code Hook

Claude Code sends commands via its `~/.claude/settings.json` hook mechanism:

```json
{
  "hooks": {
    "onOutput": {
      "command": "remembro-capture",
      "args": ["--source", "claude-code", "--cmd", "{output}"]
    }
  }
}
```

Or via a shell wrapper that intercepts `claude` and pipes output to remembro:

```bash
# ~/.local/bin/claude (wrapper)
#!/usr/bin/env bash
exec claude "$@" | tee >(remembro-capture --source claude-code)
```

### 4.3 Generic Agent Hook (FIFO Pipe)

The daemon listens on a **capture socket** at
`$XDG_RUNTIME_DIR/remembro/capture.sock` (mode 0666 so any agent can write).

Any process can push a command:

```bash
# Direct socket write
echo '{"source":"my-agent","cmd":"find . -name '*.rs'"}' \
    | nc -U -w1 "$XDG_RUNTIME_DIR/remembro/capture.sock"

# Using the convenience helper
remembro-capture --source my-agent --cmd "find . -name '*.rs'"
```

**FIFO fallback:** If the socket isn't available, the helper falls back to:

```bash
# Writing to FIFO (created by daemon at ~/.remembro/capture.fifo)
echo "my-agent:find . -name '*.rs'" > ~/.remembro/capture.fifo
```

### 4.4 Shell Hook (User Commands)

Covered in section 2.4. The hook sends every executed command (with filters)
to the daemon for automatic capture. Rate-limited client-side to avoid
flooding on rapid commands.

**Filtering rules:**

- Minimum length: 3 characters
- Skip no-ops: `ls`, `cd`, `pwd`, `clear`, `exit`
- Skip if command starts with space (user explicitly opted out)
- Skip duplicates within 60 seconds (same command, same directory)

## 5. CI/CD

### 5.1 GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
    branches: [main]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - run: nix flake check
      - run: nix build .#remembro -L

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - run: nix develop -c cargo test

  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - run: nix build .#remembro -L
      - run: |
          # Start daemon, test socket, send commands
          ./result/bin/rembrodd --daemon &
          sleep 2
          ./result/bin/rbro status
          ./result/bin/rbro add test-cmd "echo hello" test
          ./result/bin/rbro search echo
          kill %1
```

### 5.2 Release Process

```bash
# 1. Tag the release
git tag -a v2.0.0 -m "v2.0.0: daemon architecture, vector search, agent hooks"
git push origin v2.0.0

# 2. GitHub Action builds and publishes:
#    - nix package (remembro, rbro, rembrodd, remembro-hook, remembro-mcp)
#    - GitHub Release with checksums
#    - (future) Docker image, Homebrew formula
```

**Release workflow (`.github/workflows/release.yml`):**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - uses: cachix/cachix-action@v14
        with:
          name: remembro
          authToken: "${{ secrets.CACHIX_AUTH_TOKEN }}"
      - run: nix build .#remembro -L
      - name: Generate checksums
        run: |
          cd result
          sha256sum bin/* > ../checksums.txt
      - uses: softprops/action-gh-release@v2
        with:
          files: |
            checksums.txt
            result/bin/rembrodd
            result/bin/rbro
            result/bin/remembro-hook
            result/bin/remembro-mcp
          generate_release_notes: true
```

### 5.3 Update Mechanism

**Nix flake users:**

```bash
nix flake update github:timfewi/remembro
# Then rebuild: sudo nixos-rebuild switch  OR  home-manager switch
```

**Flake follows** (pinned in user's flake):

```nix
inputs.remembro.url = "github:timfewi/remembro";
# Update with: nix flake lock --update-input remembro
```

**Standalone users:**

```bash
# Check for updates
remembro update check
# → v2.0.0 installed, v2.1.0 available (2026-06-01)

# Apply update
remembro update apply
# → Downloads new binaries from GitHub release
# → Restarts daemon: systemctl --user restart rembrodd
```

## 6. Migration: v1 → v2

### What changes

| Aspect       | v1                      | v2                              |
| ------------ | ----------------------- | ------------------------------- |
| Runtime      | Bash + jq               | Rust binary                     |
| Storage      | `~/.remembro/data.json` | `~/.remembro/store.db` (SQLite) |
| Search       | Substring match         | FTS5 + vector (HNSW)            |
| Interface    | CLI only                | CLI + daemon + socket           |
| Agent hooks  | None                    | Socket, FIFO, MCP server        |
| Shell hooks  | None                    | zsh preexec (auto-capture)      |
| CI/CD        | None                    | GitHub Actions                  |
| Distribution | Nix flake               | Nix flake + GH releases         |

### Migration command

```bash
# Automatic detection during `remembro init`
$ remembro init
✔ Created ~/.remembro/
✔ Initialized SQLite database
✔ Detected v1 data at ~/.remembro/data.json
✔ Migrated 42 commands from v1 (source: migration-v1)
✔ Backed up old data → ~/.remembro/data.json.v1-bak
✔ Downloaded embedding model
✔ Started rembrodd daemon
✔ Added shell hook to ~/.zshrc

Summary:
  Commands imported: 42
  Commands skipped:  0
  Duplicates merged: 3
  Elapsed: 2.3s

Run `rbro -l` to verify.
Run `systemctl --user status rembrodd` to check daemon.
```

### Rollback

```bash
# Stop daemon, restore v1 data, uninstall v2
systemctl --user stop rembrodd
cp ~/.remembro/data.json.v1-bak ~/.remembro/data.json
# Remove v2 packages from flake inputs
```

## 7. File Layout (v2)

```
~/.remembro/
├── store.db              # SQLite database
├── store.db-wal          # SQLite WAL
├── rembro.sock           # Daemon Unix socket
├── capture.sock          # Agent capture socket
├── capture.fifo          # FIFO fallback
├── rembrodd.pid          # PID file
├── config.toml           # User configuration
├── logs/
│   ├── rembrodd.jsonl    # Active log
│   ├── rembrodd.jsonl.1  # Rotated log
│   └── ...
├── model/
│   └── all-MiniLM-L6-v2.onnx  # Embedding model
└── index/
    └── commands.hnsw     # HNSW vector index
```

## 8. Configuration (`~/.remembro/config.toml`)

```toml
# Remembro daemon configuration

[daemon]
socket_path = "/run/user/1000/remembro/rembro.sock"
capture_socket_path = "/run/user/1000/remembro/capture.sock"
pid_file = "/run/user/1000/remembro/rembrodd.pid"

[database]
path = "/home/tim/.remembro/store.db"
wal_mode = true

[vector]
enabled = true
model_path = "/home/tim/.remembro/model/all-MiniLM-L6-v2.onnx"
index_path = "/home/tim/.remembro/index/commands.hnsw"
dimensions = 384
search_limit = 20
search_threshold = 0.6

[capture]
enabled = true
rate_limit_ms = 500
skip_patterns = ["^ls$", "^cd ", "^pwd$", "^clear$", "^exit$"]
dedup_seconds = 60

[log]
level = "info"
path = "/home/tim/.remembro/logs/rembrodd.jsonl"
max_size_mb = 10
max_files = 7
```

## 9. Implementation Priority

### Phase 1 — Core (Week 1)

- [x] Rust project scaffold (Cargo workspace: `rembrodd`, `rbro`, `remembro-lib`)
- [x] SQLite schema + sqlx migrations
- [x] Unix socket JSON-RPC handler (listen + dispatch)
- [x] CLI client (`rbro`) that talks to socket
- [x] Systemd user service + socket activation
- [x] v1 → v2 migration

### Phase 2 — Intelligence (Week 2)

- [ ] FTS5 full-text search
- [ ] ONNX embedding model download & inference
- [ ] HNSW vector index (build + query)
- [ ] Hybrid search (vector + keyword weighted)

### Phase 3 — Integration (Week 3)

- [ ] Shell hooks (zsh preexec/precmd)
- [ ] Agent capture socket + FIFO
- [ ] MCP server (`remembro-mcp`)
- [ ] Home-manager module

### Phase 4 — Polish (Week 4)

- [ ] NixOS module with full options
- [ ] GitHub Actions CI + release
- [ ] Log rotation handling
- [ ] Documentation and error messages
- [ ] `remembro init` first-run wizard
