// remembro-hook — Shell hook generator & capture helper
//
// Two modes:
//   1. `remembro-hook init zsh` — Emits shell hook code for eval
//   2. `remembro-hook capture --source X --cmd Y` — Captures a command
//
// The shell hook code (emitted by `init`) is embedded from
// shell-integration.sh at build time.

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "remembro-hook",
    version,
    about = "Shell hook generator & capture helper"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate shell hook code (eval "$(remembro-hook init zsh)")
    Init {
        /// Shell type
        shell: Option<String>,
    },
    /// Capture a command from an agent
    Capture {
        /// Source identifier (e.g., "opencode", "claude-code")
        #[arg(short, long)]
        source: String,
        /// Command string to capture
        #[arg(short, long)]
        cmd: Option<String>,
    },
}

fn main() -> anyhow::Result<()> {
    match Cli::parse().command {
        Some(Commands::Init { shell }) => {
            let shell = shell.unwrap_or_else(|| "zsh".into());
            // Path is relative to this source file (crates/remembro-hook/src/).
            // ../../shell-integration.sh resolves to the workspace root.
            let code = match shell.as_str() {
                "zsh" => include_str!("../../../shell-integration.sh"),
                _ => anyhow::bail!("unsupported shell: {shell} (try zsh)"),
            };
            print!("{code}");
        }
        Some(Commands::Capture { source, cmd }) => {
            let cmd = match cmd {
                Some(c) => c,
                None => {
                    // Read from stdin (pipe mode)
                    use std::io::Read;
                    let mut buf = String::new();
                    std::io::stdin().read_to_string(&mut buf)?;
                    buf.trim().to_string()
                }
            };
            // TODO: send to daemon capture socket
            eprintln!("captured [{source}]: {cmd}");
        }
        None => {
            // Default: print help
            println!("Usage:");
            println!("  remembro-hook init zsh          Generate shell hook");
            println!("  remembro-hook capture --source X --cmd Y  Capture command");
        }
    }

    Ok(())
}
