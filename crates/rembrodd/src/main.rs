// rembrodd — Remembro daemon
//
// A background process that:
// 1. Listens on a Unix socket for JSON-RPC commands
// 2. Manages the SQLite command database
// 3. Runs vector search (when model is available)
// 4. Captures commands from shell hooks and AI agents
// 5. Reports health and metrics via the status endpoint
//
// Run as a systemd user service for auto-start.

use std::path::PathBuf;
use clap::Parser;

#[cfg(target_os = "linux")]
use sd_notify;

#[derive(Parser)]
#[command(name = "rembrodd", version, about = "Remembro daemon — terminal command memory")]
struct Args {
    /// Path to config file
    #[arg(short, long, default_value = "~/.remembro/config.toml")]
    config: PathBuf,

    /// Run once (process pending FIFO captures, then exit)
    #[arg(long)]
    once: bool,

    /// Verbose output
    #[arg(short, long)]
    verbose: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _args = Args::parse();

    // Notify systemd that we're starting up
    // The daemon will send READY=1 after socket bind in Phase 2
    #[cfg(target_os = "linux")]
    sd_notify::notify(false, &[sd_notify::NotifyState::Status("rembrodd starting up...".to_string())]).ok();

    // TODO: Phase 1 implementation
    // 1. Initialize tracing (journald + JSONL file)
    // 2. Load config
    // 3. Open database (SQLite + migrations)
    // 4. Bind Unix sockets (control + capture)
    // 5. Start JSON-RPC dispatch loop
    // 6. Notify systemd (sd_notify ready)

    eprintln!("rembrodd v{} — not yet implemented", env!("CARGO_PKG_VERSION"));
    eprintln!("See docs/DESIGN.md for the architecture plan");
    eprintln!();
    eprintln!("Planned flow:");
    eprintln!("  1. Load config from ~/.remembro/config.toml");
    eprintln!("  2. Open SQLite database at ~/.remembro/store.db");
    eprintln!("  3. Listen on $XDG_RUNTIME_DIR/remembro/rembro.sock");
    eprintln!("  4. Listen on $XDG_RUNTIME_DIR/remembro/capture.sock");
    eprintln!("  5. Dispatch JSON-RPC methods: search, list, add, delete, capture, status, ping");
    eprintln!("  6. Notify systemd: ready");
    eprintln!();
    eprintln!("Connect with: echo '{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}}' | nc -U $XDG_RUNTIME_DIR/remembro/rembro.sock");

    Ok(())
}