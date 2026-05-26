// Search layer — hybrid vector + keyword search.
//
// Phase 1: FTS5-only (always available)
// Phase 2: ONNX embedding + HNSW vector index (optional, enabled after
//          model download via `remembro init`)
//
// Vector search uses `all-MiniLM-L6-v2` (384 dim) via the `ort` crate.
// Index uses a simple HNSW implementation or the `instant-distance` crate.

use crate::protocol::Entry;
use anyhow::Result;

pub struct SearchEngine {
    // Phase 2: ONNX session
    // model: ort::Session,
    // index: HnswIndex,
}

impl SearchEngine {
    pub fn new() -> Self {
        Self {}
    }

    /// Hybrid search: combine vector similarity with FTS5 BM25 scores.
    ///
    /// Currently falls back to FTS5-only. Vector integration comes in Phase 2.
    pub async fn hybrid_search(
        &self,
        _query: &str,
        _limit: usize,
        _threshold: f64,
    ) -> Result<Vec<SearchResult>> {
        // Phase 1: return empty, caller falls back to FTS5
        Ok(vec![])
    }

    /// Compute embedding for a text string (Phase 2).
    #[allow(dead_code)]
    async fn embed(&self, _text: &str) -> Result<Vec<f32>> {
        anyhow::bail!("vector search not yet implemented — run `remembro init` to download the model");
    }

    /// Rebuild vector index from all commands (Phase 2).
    #[allow(dead_code)]
    pub async fn rebuild_index(&self) -> Result<()> {
        Ok(()) // no-op until vector search lands
    }
}

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub entry: Entry,
    pub score: f64,
}