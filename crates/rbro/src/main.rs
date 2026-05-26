// rbro — Remembro CLI client
//
// A thin CLI that communicates with rembrodd via Unix socket.
// Supports all daemon operations plus shell completion generation.

use clap::{Parser, Subcommand, ValueEnum};

/// Remembro CLI — remember and search shell commands
#[derive(Parser)]
#[command(name = "rbro", version, about = "Remember and search shell commands")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Socket path (default: $XDG_RUNTIME_DIR/remembro/rembro.sock)
    #[arg(short = 'S', long, global = true)]
    socket: Option<String>,

    /// Output as JSON
    #[arg(short = 'j', long, global = true)]
    json: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// List all saved commands
    #[command(visible_aliases = ["t", "tree"])]
    List {
        /// Filter by category
        #[arg(short, long)]
        category: Option<String>,
    },

    /// Search commands with semantic + keyword search
    /// Use "!query" for vector search, plain text for keyword
    #[command(visible_alias = "s")]
    Search {
        query: String,
        #[arg(short, long, default_value = "10")]
        limit: usize,
    },

    /// Add a new command
    #[command(visible_alias = "a")]
    Add {
        name: String,
        cmd: String,
        #[arg(default_value = "general")]
        category: String,
        #[arg(long)]
        tags: Vec<String>,
        #[arg(long)]
        desc: Option<String>,
    },

    /// Delete a command by name
    #[command(visible_alias = "d")]
    Delete { name: String },

    /// Check daemon health and stats
    Status,

    /// View recent captured commands
    Tail {
        #[arg(short, long, default_value = "10")]
        lines: usize,
    },

    /// Initialize remembro (create DB, download models, seed data)
    Init,

    /// Generate shell completions
    Completion { shell: ShellKind },

    /// Edit data directly (opens $EDITOR on DB)
    Edit,
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum ShellKind {
    Bash,
    Zsh,
    Fish,
    PowerShell,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _cli = Cli::parse();

    // TODO: Phase 1 — connect to daemon socket and dispatch

    eprintln!("rbro v{} — connecting to rembrodd...", env!("CARGO_PKG_VERSION"));
    eprintln!("(daemon not yet implemented)");
    eprintln!();
    eprintln!("Planned commands:");
    eprintln!("  rbro list                  List all commands");
    eprintln!("  rbro add <name> <cmd>      Add command");
    eprintln!("  rbro delete <name>         Delete command");
    eprintln!("  rbro search <query>        Search commands (keyword)");
    eprintln!("  rbro search '!<query>'     Search commands (vector)");
    eprintln!("  rbro status                Daemon health");
    eprintln!("  rbro tail                  Recent captures");
    eprintln!("  rbro init                  Initialize database");
    eprintln!("  rbro completion zsh        Generate shell completions");

    Ok(())
}