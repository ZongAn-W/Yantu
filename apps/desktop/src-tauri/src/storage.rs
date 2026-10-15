use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const SCHEMA_VERSION: u64 = 1;
const LOCAL_KEY: &str = "sjtu-study-planner:items-v2";
static SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StorageEnvelope {
    pub version: u64,
    pub data: Value,
    pub metadata: Value,
}

#[derive(Debug, Serialize)]
pub struct ReadResult {
    pub data: Option<Value>,
    pub metadata: Value,
    pub recovered: bool,
    pub error: Option<String>,
}

pub fn slot_path(dir: &Path, key: &str) -> Result<PathBuf, String> {
    if key == LOCAL_KEY {
        return Ok(dir.join("planner-data.json"));
    }
    let account = key.strip_prefix(&format!("{LOCAL_KEY}:cloud:"))
        .filter(|id| !id.is_empty() && id.len() <= 80 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'))
        .ok_or("无效的本地数据标识。")?;
    Ok(dir.join(format!("planner-account-{account}.json")))
}

fn backup_path(path: &Path) -> PathBuf {
    path.with_extension("json.bak")
}

fn validate(envelope: &StorageEnvelope) -> Result<(), String> {
    let data = &envelope.data;
    if envelope.version != SCHEMA_VERSION || data["version"] != 1
        || !data["profile"].is_object() || !data["profile"]["user_id"].is_string()
        || data["profile"]["planning_mode"] != "daily"
        || !["subjects", "tasks", "blocks", "logs", "fixed_events", "replan_runs", "phases"]
            .iter().all(|key| data[key].as_array().is_some_and(|rows| rows.iter().all(Value::is_object)))
        || !envelope.metadata.is_object()
    {
        return Err("本地数据版本不兼容或计划内容不完整。".into());
    }
    Ok(())
}

fn parse_envelope(path: &Path) -> Result<StorageEnvelope, String> {
    let text = fs::read(path).map_err(|e| e.to_string())?;
    let envelope: StorageEnvelope = serde_json::from_slice(&text).map_err(|e| format!("JSON 解析失败：{e}"))?;
    validate(&envelope)?;
    Ok(envelope)
}

fn unique_sibling(path: &Path, label: &str) -> PathBuf {
    let tick = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
    path.with_extension(format!("json.{label}-{tick}-{}-{}", std::process::id(), SEQUENCE.fetch_add(1, Ordering::Relaxed)))
}

fn preserve_damaged(path: &Path) -> Result<(), String> {
    if path.exists() {
        fs::copy(path, unique_sibling(path, "corrupt")).map_err(|e| format!("保留损坏文件失败：{e}"))?;
    }
    Ok(())
}

pub fn read_slot(path: &Path) -> ReadResult {
    let backup = backup_path(path);
    let empty = || ReadResult {
        data: None,
        metadata: json!({ "version": SCHEMA_VERSION, "revision": 0, "pending": false, "base": null }),
        recovered: false,
        error: None,
    };
    if !path.exists() && !backup.exists() { return empty(); }
    match parse_envelope(path) {
        Ok(envelope) => ReadResult { data: Some(envelope.data), metadata: envelope.metadata, ..empty() },
        Err(main_error) => match parse_envelope(&backup) {
            Ok(envelope) => {
                let repaired = preserve_damaged(path).and_then(|_| {
                    let bytes = serde_json::to_vec_pretty(&envelope).map_err(|e| e.to_string())?;
                    atomic_replace(path, &bytes)
                });
                let message = match repaired {
                    Ok(()) => format!("主数据无法读取，已从最近备份恢复，原文件已另存：{main_error}"),
                    Err(error) => format!("已载入最近备份，但修复主文件失败：{error}"),
                };
                ReadResult { data: Some(envelope.data), metadata: envelope.metadata, recovered: true, error: Some(message) }
            }
            Err(backup_error) => ReadResult {
                error: Some(format!("主数据和备份都无法读取。主文件：{main_error}；备份：{backup_error}")),
                ..empty()
            },
        },
    }
}

pub fn write_slot(path: &Path, envelope: &StorageEnvelope, recovery: bool) -> Result<(), String> {
    validate(envelope)?;
    let backup = backup_path(path);
    if path.exists() {
        if parse_envelope(path).is_ok() {
            let previous = fs::read(path).map_err(|e| e.to_string())?;
            atomic_replace(&backup, &previous)?;
        } else {
            if !recovery && parse_envelope(&backup).is_err() {
                return Err("原数据和备份无法读取，已停止保存。请重试读取或从 JSON 恢复。".into());
            }
            preserve_damaged(path)?;
        }
    } else if backup.exists() && parse_envelope(&backup).is_err() && !recovery {
        return Err("最近备份无法读取，已停止保存。请从 JSON 恢复。".into());
    }
    let bytes = serde_json::to_vec_pretty(envelope).map_err(|e| e.to_string())?;
    atomic_replace(path, &bytes)
}

pub fn atomic_replace(path: &Path, bytes: &[u8]) -> Result<(), String> {
    atomic_replace_with(path, bytes, replace_existing)
}

fn atomic_replace_with(path: &Path, bytes: &[u8], replace: impl FnOnce(&Path, &Path) -> Result<(), String>) -> Result<(), String> {
    let temp = unique_sibling(path, "tmp");
    let mut file = fs::OpenOptions::new().write(true).create_new(true).open(&temp).map_err(|e| format!("创建临时文件失败：{e}"))?;
    file.write_all(bytes).map_err(|e| format!("写入临时文件失败：{e}"))?;
    file.sync_all().map_err(|e| format!("刷新临时文件失败：{e}"))?;
    drop(file);
    // Failed replacements leave the original and the completed temporary file intact.
    replace(&temp, path)
}

#[cfg(windows)]
fn replace_existing(temp: &Path, target: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
    let source: Vec<u16> = temp.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let destination: Vec<u16> = target.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let replaced = unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) };
    if replaced == 0 { return Err(format!("替换本地数据失败：{}", std::io::Error::last_os_error())); }
    Ok(())
}

#[cfg(not(windows))]
fn replace_existing(temp: &Path, target: &Path) -> Result<(), String> {
    fs::rename(temp, target).map_err(|e| format!("替换本地数据失败：{e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_path() -> PathBuf {
        let dir = unique_sibling(&std::env::temp_dir().join("sjtu-storage"), "test");
        fs::create_dir_all(&dir).unwrap();
        dir.join("planner-data.json")
    }

    fn sample(name: &str) -> StorageEnvelope {
        StorageEnvelope { version: 1, data: json!({
            "version": 1, "profile": { "user_id": "local-demo", "planning_mode": "daily", "target_school": name },
            "subjects": [], "tasks": [], "blocks": [], "logs": [], "fixed_events": [], "replan_runs": [], "phases": []
        }), metadata: json!({ "version": 1, "pending": true, "revision": 7, "base": null }) }
    }

    #[test]
    fn first_save_and_reopen_keep_offline_metadata() {
        let path = test_path();
        assert!(read_slot(&path).error.is_none());
        write_slot(&path, &sample("offline edit"), false).unwrap();
        let loaded = read_slot(&path);
        assert_eq!(loaded.data.unwrap()["profile"]["target_school"], "offline edit");
        assert_eq!(loaded.metadata["pending"], true);
        assert_eq!(loaded.metadata["revision"], 7);
    }

    #[test]
    fn failed_atomic_replace_keeps_original_bytes() {
        let path = test_path();
        write_slot(&path, &sample("old"), false).unwrap();
        let original = fs::read(&path).unwrap();
        let result = atomic_replace_with(&path, b"new", |_, _| Err("simulated replacement failure".into()));
        assert!(result.is_err());
        assert_eq!(fs::read(&path).unwrap(), original);
    }

    #[test]
    fn corrupt_main_recovers_backup_and_preserves_it_on_next_save() {
        let path = test_path();
        write_slot(&path, &sample("first"), false).unwrap();
        write_slot(&path, &sample("second"), false).unwrap();
        fs::write(&path, b"{broken").unwrap();
        let recovered = read_slot(&path);
        assert!(recovered.recovered);
        assert_eq!(recovered.data.unwrap()["profile"]["target_school"], "first");
        assert!(!read_slot(&path).recovered);
        write_slot(&path, &sample("after recovery"), false).unwrap();
        assert_eq!(parse_envelope(&backup_path(&path)).unwrap().data["profile"]["target_school"], "first");
    }

    #[test]
    fn both_corrupt_require_explicit_recovery() {
        let path = test_path();
        fs::write(&path, b"broken main").unwrap();
        fs::write(backup_path(&path), b"broken backup").unwrap();
        assert!(read_slot(&path).data.is_none());
        assert!(write_slot(&path, &sample("new"), false).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"broken main");
        write_slot(&path, &sample("imported"), true).unwrap();
        assert_eq!(fs::read(backup_path(&path)).unwrap(), b"broken backup");
        assert!(read_slot(&path).data.is_some());
    }

    #[test]
    fn demo_and_accounts_use_separate_safe_paths() {
        let path = test_path();
        let dir = path.parent().unwrap();
        let demo = slot_path(dir, LOCAL_KEY).unwrap();
        let account = slot_path(dir, &format!("{LOCAL_KEY}:cloud:user-a")).unwrap();
        write_slot(&demo, &sample("demo"), false).unwrap();
        write_slot(&account, &sample("account"), false).unwrap();
        assert_ne!(read_slot(&demo).data, read_slot(&account).data);
        assert!(slot_path(dir, &format!("{LOCAL_KEY}:cloud:../escape")).is_err());
    }

    #[test]
    fn export_and_import_round_trip() {
        let path = test_path();
        let original = sample("exported");
        let export_path = path.with_file_name("export.json");
        atomic_replace(&export_path, &serde_json::to_vec(&original.data).unwrap()).unwrap();
        let imported = StorageEnvelope { data: serde_json::from_slice(&fs::read(export_path).unwrap()).unwrap(), ..original.clone() };
        write_slot(&path, &imported, true).unwrap();
        assert_eq!(read_slot(&path).data.unwrap(), original.data);
    }
}
