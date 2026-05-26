// Remembro shared library
//
// Core types, protocol, database, and search logic shared between
// rembrodd (daemon) and rbro (CLI client).

pub mod protocol;
pub mod db;
pub mod search;
pub mod config;

/// Re-export common types
pub use protocol::{Request, Response, Entry};
pub use config::Config;

/// Version string
pub const VERSION: &str = env!("CARGO_PKG_VERSION");