# Remembro v2 — agent integration configuration examples

## OpenCode

### Option A: Post-tool hook

Place in `opencode.json` or `.opencode/config.json`:

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

### Option B: MCP server

Place in `~/.config/opencode/mcp.json` or `opencode.json`:

```json
{
  "mcpServers": {
    "remembro": {
      "command": "remembro-mcp",
      "args": [],
      "env": {
        "REMEMBRO_SOCKET": "${XDG_RUNTIME_DIR}/remembro/rembro.sock"
      }
    }
  }
}
```

The MCP server exposes:

- **Tool: `remember_command`** — Explicitly store a command in remembro
  - Params: `name` (str), `cmd` (str), `category?` (str), `tags?` (str[]), `description?` (str)
- **Tool: `search_commands`** — Vector + keyword search through remembro's DB
  - Params: `query` (str), `limit?` (int, default 5), `threshold?` (float, default 0.6)
- **Resource: `remembro://status`** — Daemon health + stats

## Claude Code

### Option A: Hook in settings

Place in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "postTool": {
      "command": "remembro-capture",
      "args": ["--source", "claude-code", "--cmd", "{output}"]
    }
  }
}
```

### Option B: Shell wrapper

Install as `~/.local/bin/claude`:

```bash
#!/usr/bin/env bash
# Wrapper that captures all Claude Code output to remembro
exec claude "$@" | tee >(
  remembro-capture --source claude-code --stdin
)
```

## Generic Agent (any process)

### Via Unix socket (direct)

```bash
curl -s --unix-socket "$XDG_RUNTIME_DIR/remembro/capture.sock" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"capture","params":{"source":"my-agent","cmd":"kubectl get pods"}}'
```

### Via remembro-capture helper

```bash
remembro-capture --source my-agent --cmd "docker compose up -d"

# Or pipe:
echo "npm run dev" | remembro-capture --source pipe
```

### Via FIFO (no socket available)

```bash
echo "my-agent:npm test" > ~/.remembro/capture.fifo
```

## Shell hook (zsh)

Add to `~/.zshrc`:

```bash
eval "$(remembro-hook init zsh)"
```

Filters applied:

- Min 3 characters
- Skip no-ops: ls, cd, pwd, clear, exit
- Skip commands prefixed with space
- Rate-limited: 500ms between duplicates
- Dedup: same command within 60s (respects working directory)
