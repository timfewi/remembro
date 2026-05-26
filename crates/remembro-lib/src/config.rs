// Configuration — reads ~/.remembro/config.toml with sensible defaults.

use anyhow::Result;
use serde::Deserialize;
use shellexpand;
use std::path::PathBuf;

fn default_socket_path() -> PathBuf {
    if let Ok(runtime) = std::env::var("XDG_RUNTIME_DIR") {
        PathBuf::from(runtime).join("remembro/rembro.sock")
    } else {
        shellexpand::tilde("~/.remembro/rembro.sock")
            .into_owned()
            .into()
    }
}

fn default_capture_socket() -> PathBuf {
    if let Ok(runtime) = std::env::var("XDG_RUNTIME_DIR") {
        PathBuf::from(runtime).join("remembro/capture.sock")
    } else {
        shellexpand::tilde("~/.remembro/capture.sock")
            .into_owned()
            .into()
    }
}

fn default_db_path() -> PathBuf {
    shellexpand::tilde("~/.remembro/store.db")
        .into_owned()
        .into()
}

fn default_log_path() -> PathBuf {
    shellexpand::tilde("~/.remembro/logs/rembrodd.jsonl")
        .into_owned()
        .into()
}

fn default_true() -> bool {
    true
}
fn default_max_files() -> usize {
    7
}
fn default_max_size() -> usize {
    10
}

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub daemon: DaemonConfig,
    #[serde(default)]
    pub database: DatabaseConfig,
    #[serde(default)]
    pub vector: VectorConfig,
    #[serde(default)]
    pub capture: CaptureConfig,
    #[serde(default)]
    pub log: LogConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DaemonConfig {
    #[serde(default = "default_socket_path")]
    pub socket_path: PathBuf,
    #[serde(default = "default_capture_socket")]
    pub capture_socket_path: PathBuf,
    #[serde(default)]
    pub capture_fifo_path: PathBuf,
    #[serde(default)]
    pub pid_file: PathBuf,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        Self {
            socket_path: default_socket_path(),
            capture_socket_path: default_capture_socket(),
            capture_fifo_path: shellexpand::tilde("~/.remembro/capture.fifo")
                .into_owned()
                .into(),
            pid_file: default_socket_path().with_file_name("rembrodd.pid"),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    #[serde(default = "default_db_path")]
    pub path: PathBuf,
    #[serde(default = "default_true")]
    pub wal_mode: bool,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            path: default_db_path(),
            wal_mode: true,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct VectorConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub model_path: PathBuf,
    #[serde(default)]
    pub index_path: PathBuf,
    #[serde(default = "default_dimensions")]
    pub dimensions: usize,
    #[serde(default = "default_limit")]
    pub search_limit: usize,
    #[serde(default = "default_threshold")]
    pub search_threshold: f64,
}

fn default_dimensions() -> usize {
    384
}
fn default_limit() -> usize {
    20
}
fn default_threshold() -> f64 {
    0.6
}

impl Default for VectorConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            model_path: shellexpand::tilde("~/.remembro/model/all-MiniLM-L6-v2.onnx")
                .into_owned()
                .into(),
            index_path: shellexpand::tilde("~/.remembro/index/commands.hnsw")
                .into_owned()
                .into(),
            dimensions: 384,
            search_limit: 20,
            search_threshold: 0.6,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct CaptureConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_rate_limit")]
    pub rate_limit_ms: u64,
    #[serde(default)]
    pub skip_patterns: Vec<String>,
    #[serde(default = "default_dedup")]
    pub dedup_seconds: u64,
}

fn default_rate_limit() -> u64 {
    500
}
fn default_dedup() -> u64 {
    60
}

impl Default for CaptureConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            rate_limit_ms: 500,
            skip_patterns: vec!["^ls$".into(), "^cd ".into(), "^pwd$".into()],
            dedup_seconds: 60,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct LogConfig {
    #[serde(default = "default_log_level")]
    pub level: String,
    #[serde(default = "default_log_path")]
    pub path: PathBuf,
    #[serde(default = "default_max_size")]
    pub max_size_mb: usize,
    #[serde(default = "default_max_files")]
    pub max_files: usize,
    #[serde(default = "default_true")]
    pub also_journal: bool,
}

fn default_log_level() -> String {
    "info".into()
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: "info".into(),
            path: default_log_path(),
            max_size_mb: 10,
            max_files: 7,
            also_journal: true,
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            daemon: DaemonConfig::default(),
            database: DatabaseConfig::default(),
            vector: VectorConfig::default(),
            capture: CaptureConfig::default(),
            log: LogConfig::default(),
        }
    }
}

impl Config {
    /// Load config from the default path (~/.remembro/config.toml).
    pub fn load() -> Result<Self> {
        let path: PathBuf = shellexpand::tilde("~/.remembro/config.toml")
            .into_owned()
            .into();

        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            Ok(toml::from_str(&content)?)
        } else {
            Ok(Self::default())
        }
    }
}
