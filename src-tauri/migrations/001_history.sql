CREATE TABLE IF NOT EXISTS explanations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at_ms INTEGER NOT NULL,
    source_app TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    capture_method TEXT NOT NULL,
    selected_text TEXT NOT NULL,
    context_before TEXT NOT NULL,
    context_after TEXT NOT NULL,
    preset_id TEXT NOT NULL,
    preset_version INTEGER NOT NULL,
    prompt_text TEXT NOT NULL,
    model_id TEXT NOT NULL,
    reply TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS explanations_created_at_idx ON explanations(created_at_ms DESC, id DESC);
