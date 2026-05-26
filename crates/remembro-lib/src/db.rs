// Database layer — SQLite with FTS5 for keyword search.
//
// Schema:
//   commands          — primary table (id, name, cmd, category, tags, ...)
//   commands_fts      — FTS5 virtual table for full-text search
//   idx_*             — B-tree indexes on category, name, source

use anyhow::Result;
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use crate::protocol::Entry;

pub struct Database {
    pool: SqlitePool,
}

impl Database {
    /// Open or create the database at `path`.
    pub async fn open(path: &str) -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(4)
            .connect(&format!("sqlite://{path}?mode=rwc"))
            .await?;

        sqlx::migrate!("./migrations").run(&pool).await?;

        // Enable WAL mode for better concurrent performance
        sqlx::query("PRAGMA journal_mode=WAL").execute(&pool).await?;

        Ok(Self { pool })
    }

    /// Sanitize FTS5 query to prevent syntax errors from malformed input.
    fn sanitize_fts5(query: &str) -> String {
        let terms: Vec<&str> = query.split_whitespace().collect();
        if terms.is_empty() {
            return String::new();
        }
        terms
            .iter()
            .map(|t| {
                let cleaned: String = t
                    .chars()
                    .filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
                    .collect();
                format!("\"{}\"", cleaned)
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Search commands by FTS5 keyword match.
    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<Entry>> {
        let safe_query = Self::sanitize_fts5(query);
        if safe_query.is_empty() {
            return Ok(vec![]);
        }

        let rows = sqlx::query_as::<_, Entry>(
            r#"
            SELECT c.*
            FROM commands c
            JOIN commands_fts fts ON c.rowid = fts.rowid
            WHERE commands_fts MATCH ?1
            ORDER BY rank
            LIMIT ?2
            "#
        )
        .bind(safe_query)
        .bind(limit as i64)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }

    /// List all commands, optionally filtered by category.
    pub async fn list(&self, category: Option<&str>, limit: usize) -> Result<Vec<Entry>> {
        let rows = if let Some(cat) = category {
            sqlx::query_as::<_, Entry>(
                "SELECT * FROM commands WHERE category = ?1 ORDER BY name LIMIT ?2"
            )
            .bind(cat)
            .bind(limit as i64)
            .fetch_all(&self.pool).await?
        } else {
            sqlx::query_as::<_, Entry>(
                "SELECT * FROM commands ORDER BY category, name LIMIT ?1"
            )
            .bind(limit as i64)
            .fetch_all(&self.pool).await?
        };

        Ok(rows)
    }

    /// Insert a new command.
    pub async fn insert(&self, entry: &Entry) -> Result<String> {
        sqlx::query(
            r#"
            INSERT INTO commands (id, name, cmd, category, description, tags, notes, source, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            "#
        )
        .bind(&entry.id)
        .bind(&entry.name)
        .bind(&entry.cmd)
        .bind(&entry.category)
        .bind(&entry.description)
        .bind(&entry.tags)
        .bind(&entry.notes)
        .bind(&entry.source)
        .execute(&self.pool)
        .await?;

        Ok(entry.id.clone())
    }

    /// Delete a command by name.
    pub async fn delete(&self, name: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM commands WHERE name = ?1")
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Get total command count.
    pub async fn count(&self) -> Result<u64> {
        let (count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM commands")
            .fetch_one(&self.pool).await?;
        Ok(count as u64)
    }
}