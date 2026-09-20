use rusqlite::{params, Connection};
use serde::Serialize;
use std::{fs, time::Duration};
use tauri::Manager;

#[derive(Clone, Serialize)]
pub struct HistoryRecord {
    pub id: i64,
    pub created_at_ms: i64,
    pub source_app: String,
    pub bundle_id: String,
    pub capture_method: String,
    pub selected_text: String,
    pub context_before: String,
    pub context_after: String,
    pub preset_id: String,
    pub preset_version: i64,
    pub prompt_text: String,
    pub model_id: String,
    pub reply: String,
}

fn open(app: &tauri::AppHandle) -> Result<Connection, String> {
    let directory = app.path().app_data_dir().map_err(|_| "Could not find app data directory")?;
    fs::create_dir_all(&directory).map_err(|_| "Could not create app data directory")?;
    let connection = Connection::open(directory.join("history.sqlite3"))
        .map_err(|_| "Could not open local history")?;
    connection.busy_timeout(Duration::from_secs(2)).map_err(|_| "Could not configure local history")?;
    Ok(connection)
}

pub fn init(app: &tauri::AppHandle) -> Result<(), String> {
    let mut db = open(app)?;
    let version: i64 = db.query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|_| "Could not inspect history schema")?;
    if version > 1 { return Err("History schema is newer than this app".into()); }
    if version == 0 {
        let transaction = db.transaction().map_err(|_| "Could not migrate history")?;
        transaction.execute_batch(include_str!("../migrations/001_history.sql"))
            .map_err(|_| "Could not migrate history")?;
        transaction.execute_batch("PRAGMA user_version = 1")
            .map_err(|_| "Could not migrate history")?;
        transaction.commit().map_err(|_| "Could not migrate history")?;
    }
    Ok(())
}

pub fn insert(app: &tauri::AppHandle, record: &HistoryRecord) -> Result<(), String> {
    let db = open(app)?;
    insert_into(&db, record)
}

fn insert_into(db: &Connection, record: &HistoryRecord) -> Result<(), String> {
    db.execute(
        "INSERT INTO explanations (created_at_ms, source_app, bundle_id, capture_method, selected_text, context_before, context_after, preset_id, preset_version, prompt_text, model_id, reply) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        params![record.created_at_ms, record.source_app, record.bundle_id, record.capture_method, record.selected_text, record.context_before, record.context_after, record.preset_id, record.preset_version, record.prompt_text, record.model_id, record.reply],
    ).map_err(|_| "Could not save explanation to local history")?;
    Ok(())
}

pub fn list(app: &tauri::AppHandle, query: &str, offset: u32) -> Result<Vec<HistoryRecord>, String> {
    let db = open(app)?;
    list_from(&db, query, offset)
}

fn list_from(db: &Connection, query: &str, offset: u32) -> Result<Vec<HistoryRecord>, String> {
    if query.len() > 200 || offset > 100_000 { return Err("Search is too large".into()); }
    let pattern = format!("%{}%", query.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_"));
    let mut statement = db.prepare(
        "SELECT id, created_at_ms, source_app, bundle_id, capture_method, selected_text, context_before, context_after, preset_id, preset_version, prompt_text, model_id, reply FROM explanations WHERE (?1 = '' OR selected_text LIKE ?2 ESCAPE '\\' OR source_app LIKE ?2 ESCAPE '\\' OR preset_id LIKE ?2 ESCAPE '\\' OR reply LIKE ?2 ESCAPE '\\') ORDER BY created_at_ms DESC, id DESC LIMIT 100 OFFSET ?3"
    ).map_err(|_| "Could not search history")?;
    let rows = statement.query_map(params![query, pattern, offset], |row| Ok(HistoryRecord {
        id: row.get(0)?, created_at_ms: row.get(1)?, source_app: row.get(2)?, bundle_id: row.get(3)?,
        capture_method: row.get(4)?, selected_text: row.get(5)?, context_before: row.get(6)?,
        context_after: row.get(7)?, preset_id: row.get(8)?, preset_version: row.get(9)?,
        prompt_text: row.get(10)?, model_id: row.get(11)?, reply: row.get(12)?,
    })).map_err(|_| "Could not search history")?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|_| "Could not read history".into())
}

pub fn delete(app: &tauri::AppHandle, id: i64) -> Result<bool, String> {
    let db = open(app)?;
    delete_from(&db, id)
}

fn delete_from(db: &Connection, id: i64) -> Result<bool, String> {
    db.execute("DELETE FROM explanations WHERE id = ?", [id])
        .map(|deleted| deleted > 0).map_err(|_| "Could not delete history entry".into())
}

pub fn clear(app: &tauri::AppHandle) -> Result<(), String> {
    let db = open(app)?;
    clear_from(&db)
}

fn clear_from(db: &Connection) -> Result<(), String> {
    db.execute("DELETE FROM explanations", [])
        .map_err(|_| "Could not clear history")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn memory_db() -> Connection {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch(include_str!("../migrations/001_history.sql")).unwrap();
        db
    }

    fn record(text: &str) -> HistoryRecord {
        HistoryRecord {
            id: 0, created_at_ms: 123, source_app: "TextEdit".into(), bundle_id: "com.apple.TextEdit".into(),
            capture_method: "ax_selected_text".into(), selected_text: text.into(),
            context_before: String::new(), context_after: String::new(),
            preset_id: "explain_simply".into(), preset_version: 1,
            prompt_text: "Explain plainly".into(), model_id: "test-model".into(), reply: "A reply".into(),
        }
    }

    #[test]
    fn history_search_delete_and_clear() {
        let db = memory_db();
        insert_into(&db, &record("100% selected_\\text")).unwrap();
        insert_into(&db, &record("another passage")).unwrap();
        let matching = list_from(&db, "selected_\\", 0).unwrap();
        assert_eq!(matching.len(), 1);
        assert_eq!(matching[0].selected_text, "100% selected_\\text");
        assert!(list_from(&db, "100%", 0).unwrap().len() == 1);
        assert!(delete_from(&db, matching[0].id).unwrap());
        assert!(!delete_from(&db, matching[0].id).unwrap());
        assert!(list_from(&db, "selected_", 0).unwrap().is_empty());
        assert_eq!(list_from(&db, "", 0).unwrap().len(), 1);
        clear_from(&db).unwrap();
        assert!(list_from(&db, "", 0).unwrap().is_empty());
    }

    #[test]
    fn existing_history_and_new_visual_methods_coexist_without_schema_changes() {
        let db = memory_db();
        for method in ["automated_copy", "ax_selected_text", "ax_bounds_ocr", "visual_drag_ocr"] {
            let mut item = record(method);
            item.capture_method = method.into();
            insert_into(&db, &item).unwrap();
        }
        let listed = list_from(&db, "", 0).unwrap();
        assert_eq!(listed.len(), 4);
        for method in ["automated_copy", "ax_selected_text", "ax_bounds_ocr", "visual_drag_ocr"] {
            assert!(listed.iter().any(|item| item.capture_method == method));
        }
        assert!(listed.iter().all(|item| item.context_before.is_empty() && item.context_after.is_empty()));
    }
}
