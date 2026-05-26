# Remembro v2

A terminal daemon that remembers, searches, and captures shell commands.

```
rbro docker compose up --build   # ← remember commands
rbro !docker compose             # ← instant vector search
rbro -l                          # ← browse by category
```

## Architecture

```
┌──────────────────────────────────────────┐
│           rembrodd (daemon)               │
│  ┌──────────┐  ┌──────────────┐         │
│  │ JSON-RPC  │  │ Vector       │         │
│  │ Socket I/O│  │ Search       │         │
│  └─────┬────┘  │ (HNSW+ONNX)  │         │
│        │       └──────┬───────┘         │
│  ┌─────┴──────────────┴───────┐         │
│  │     SQLite (FTS5 + WAL)    │         │
│  └────────────────────────────┘         │
└──────────────────────────────────────────┘
```

- **`rembrodd`** — background daemon (systemd user service)
- **`rbro`** — CLI client (talks to daemon via Unix socket)
- **`remembro-hook`** — shell hook generator (`eval "$(remembro-hook init zsh)"`)
- **`remembro-mcp`** — MCP server for AI agents (OpenCode, Claude Code)
- **`remembro-capture`** — agent capture helper (push commands from any process)

## Installation

### NixOS (with module)

```nix
{
  inputs.remembro.url = "github:timfewi/remembro";

  outputs = { self, nixpkgs, remembro, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        remembro.nixosModules.default
        {
          services.remembro = {
            enable = true;
            user = "tim";
            vectorSearch.enable = true;
          };
        }
      ];
    };
  };
}
```

### Home-manager

```nix
{
  imports = [ inputs.remembro.homeManagerModules.default ];
  services.remembro = {
    enable = true;
    shellIntegration = true;
  };
}
```

### Standalone (without Nix)

```bash
# Download latest release
curl -LO https://github.com/timfewi/remembro/releases/latest/download/rembrodd
chmod +x rembrodd && sudo mv rembrodd /usr/local/bin/

# Initialize
remembro init

# Start daemon
systemctl --user enable --now rembrodd
```

## Usage

```bash
# List commands by category
rbro -l

# Vector search (semantic)
rbro !docker compose build

# Keyword search (FTS5 fallback)
rbro docker

# Add a command
rbro -a docker-build "docker build -t myapp ." containers

# Delete a command
rbro -d docker-build

# Check daemon health
rbro status

# See recent captures
rbro tail --lines 10
```

## Agent Integration

Remembro captures commands from any source:

```bash
# Shell hooks (automatic)
eval "$(remembro-hook init zsh)"

# AI agents via MCP
remembro-mcp                    # OpenCode, Claude Code

# Any process via socket
remembro-capture --source my-agent --cmd "kubectl get pods"
```

See [docs/AGENT_INTEGRATION.md](docs/AGENT_INTEGRATION.md) for full details.

## Design

See [docs/DESIGN.md](docs/DESIGN.md) for complete architecture, deployment strategy,
monitoring/logging design, and CI/CD pipeline.

## Quick Start

```bash
# 1. Initialize (creates ~/.remembro/, DB, seeds data)
remembro init

# 2. Verify daemon is running
systemctl --user status rembrodd

# 3. Browse your command library
rbro -l

# 4. Search
rbro !postgres backup

# 5. Add shell hooks (add to .zshrc)
eval "$(remembro-hook init zsh)"
```

## Migration from v1

```bash
# If you have ~/.remembro/data.json from v1:
remembro migrate
# → Imports all commands into SQLite
# → Backs up v1 data to data.json.v1-bak
# → Generates migration report
```

## Development

```bash
nix develop   # Enter dev shell (Rust + tools)
cargo build   # Build the daemon
cargo test    # Run tests
cargo run --bin rbro -- -l  # Quick test
```

## License

MIT
