// Protocol types for remembro JSON-RPC communication over Unix sockets.

use serde::{Deserialize, Serialize};

// ── JSON-RPC types ──────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct Request {
    pub jsonrpc: String,
    #[serde(default)]
    pub id: Option<u64>,
    pub method: String,
    #[serde(default)]
    pub params: serde_json::Value,
}

#[derive(Debug, Serialize)]
pub struct Response {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ResponseError>,
}

#[derive(Debug, Serialize)]
pub struct ResponseError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

impl Response {
    pub fn ok(id: Option<u64>, result: serde_json::Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn err(id: Option<u64>, code: i64, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id,
            result: None,
            error: Some(ResponseError {
                code,
                message: message.into(),
                data: None,
            }),
        }
    }
}

// ── Domain types ────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub cmd: String,
    pub category: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    pub source: String,
    pub created_at: String,
    pub updated_at: String,
    pub last_used: Option<String>,
    pub hit_count: u64,
}

impl Entry {
    /// Deserialize the JSON `tags` field into a `Vec<String>`.
    pub fn tags_vec(&self) -> Vec<String> {
        match &self.tags {
            Some(json) => serde_json::from_str(json).unwrap_or_default(),
            None => Vec::new(),
        }
    }

    /// Serialize a `Vec<String>` into the JSON `tags` field.
    pub fn set_tags(&mut self, tags: Vec<String>) {
        self.tags = Some(serde_json::to_string(&tags).unwrap_or_default());
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Status {
    pub pid: u32,
    pub uptime_sec: u64,
    pub memory_kb: u64,
    pub cpu_pct: f64,
    pub db_size_kb: u64,
    pub index_size_kb: u64,
    pub commands_total: u64,
    pub captures_total: u64,
    pub searches_total: u64,
}

#[derive(Debug, Deserialize)]
pub struct SearchParams {
    pub query: String,
    #[serde(default = "default_limit")]
    pub limit: usize,
    #[serde(default = "default_threshold")]
    pub threshold: f64,
}

fn default_limit() -> usize {
    20
}
fn default_threshold() -> f64 {
    0.6
}

#[derive(Debug, Deserialize)]
pub struct AddParams {
    pub name: String,
    pub cmd: String,
    #[serde(default = "default_category")]
    pub category: String,
    pub tags: Option<Vec<String>>,
    pub description: Option<String>,
}

fn default_category() -> String {
    "general".into()
}

#[derive(Debug, Deserialize)]
pub struct CaptureParams {
    pub source: String,
    pub cmd: String,
}

// ── Error codes ────────────────────────────────────────────

pub const ERR_METHOD_NOT_FOUND: i64 = -32601;
pub const ERR_INVALID_PARAMS: i64 = -32602;
pub const ERR_INTERNAL: i64 = -32603;
pub const ERR_NOT_FOUND: i64 = -32001;
pub const ERR_DAEMON_NOT_RUNNING: i64 = -32002;
