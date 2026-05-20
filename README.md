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

# Add command
remembro -a "mycmd" "echo hello" "test"

# Search command
remembro "mycmd"
```

## Dependencies
- `jq`
