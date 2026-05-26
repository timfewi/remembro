// remembro-mcp — MCP server for AI agent integration
//
// Implements the Model Context Protocol so AI agents (OpenCode, Claude Code)
// can search and store commands in remembro.
//
// Exposes:
//   - Tool: remember_command(name, cmd, category?, tags?, description?)
//   - Tool: search_commands(query, limit?, threshold?)
//   - Resource: remembro://status

use clap::Parser;

#[derive(Parser)]
#[command(name = "remembro-mcp", version)]
struct Args {
    /// Path to daemon socket
    #[arg(short, long)]
    socket: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // Allow REMEMBRO_SOCKET env var to override CLI arg (matching AGENT_INTEGRATION.md)
    let _socket = args.socket.or_else(|| std::env::var("REMEMBRO_SOCKET").ok());

    eprintln!("remembro-mcp v{} — not yet implemented", env!("CARGO_PKG_VERSION"));
    eprintln!();
    eprintln!("Will implement MCP protocol with:");
    eprintln!("  Tool: remember_command(name, cmd, category, tags, description)");
    eprintln!("  Tool: search_commands(query, limit, threshold)");
    eprintln!("  Resource: remembro://status");
    eprintln!();
    eprintln!("Add to opencode.json:");
    eprintln!("  {{\"mcpServers\":{{\"remembro\":{{\"command\":\"remembro-mcp\"}}}}}}");

    Ok(())
}