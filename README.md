# Remembro

A simple command-line tool to remember and search for shell commands.

## Installation

### Using Nix Flake
If you are using Nix, you can run `remembro` directly without installing:

```bash
nix run . -- --help
```

Or add it to your `flake.nix` inputs.

### Manual
1. Ensure `jq` is installed.
2. Place the `remembro` script in your `$PATH`.

## Usage
```bash
# List commands
remembro -l

# List commands grouped by category
remembro -t

# Add command
remembro -a "mycmd" "echo hello" "test"

# Search command
remembro "mycmd"
```

Commands are stored in `~/.remembro/data.json`. Entries may include optional
`description`, `tags`, and `notes` fields; list and search output will render
those fields when present. `seed-data.json` contains a larger starter database
for NixOS, Linux, Git, Docker Compose, Rust/Axum/SQLx, Next.js/Drizzle,
Bun/Biome, Python tooling, MCP, OpenCode, OpenFang/ZeroClaw, and common
development workflows.

## Dependencies
- `jq`
