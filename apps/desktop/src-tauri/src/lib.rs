use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager, Runtime};

const SCHEMA_VERSION: u64 = 1;
const DATA_FILE: &str = "planner-data.json";
const BACKUP_FILE: &str = "planner-data.json.bak";

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

fn data_dir<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let path = app.path().app_data_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&path).map_err(|e| format!("创建本地数据目录失败：{e}"))?;
    Ok(path)
}

fn data_path<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(DATA_FILE))
}

fn backup_path<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    Ok(data_dir(app)?.join(BACKUP_FILE))
}

fn parse_envelope(path: &Path) -> Result<StorageEnvelope, String> {
    let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let envelope: StorageEnvelope = serde_json::from_str(&text).map_err(|e| format!("JSON 解析失败：{e}"))?;
    if envelope.version != SCHEMA_VERSION || !envelope.data.is_object() {
        return Err("本地数据版本不兼容或内容不是计划对象。".into());
    }
    Ok(envelope)
}

#[tauri::command]
pub fn read_planner_data<R: Runtime>(app: AppHandle<R>) -> Result<ReadResult, String> {
    let main = data_path(&app)?;
    let backup = backup_path(&app)?;
    // A new installation has no files yet. This is a clean empty state, not corruption.
    if !main.exists() && !backup.exists() {
        return Ok(ReadResult {
            data: None,
            metadata: serde_json::json!({ "version": SCHEMA_VERSION, "revision": 0, "pending": false, "base": null }),
            recovered: false,
            error: None,
        });
    }
    match parse_envelope(&main) {
        Ok(envelope) => Ok(ReadResult {
            data: Some(envelope.data),
            metadata: envelope.metadata,
            recovered: false,
            error: None,
        }),
        Err(main_error) => match parse_envelope(&backup) {
            Ok(envelope) => Ok(ReadResult {
                data: Some(envelope.data),
                metadata: envelope.metadata,
                recovered: true,
                error: Some(format!("主数据损坏，已从最近备份恢复：{main_error}")),
            }),
            Err(backup_error) => Ok(ReadResult {
                data: None,
                metadata: serde_json::json!({ "version": SCHEMA_VERSION, "revision": 0, "pending": false, "base": null }),
                recovered: false,
                error: Some(format!("主数据和备份都无法读取。主文件：{main_error} 备份：{backup_error}")),
            }),
        },
    }
}

fn atomic_replace(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let temp = path.with_extension(format!("json.tmp-{}", std::process::id()));
    let mut file = fs::File::create(&temp).map_err(|e| format!("创建临时文件失败：{e}"))?;
    file.write_all(bytes).map_err(|e| format!("写入临时文件失败：{e}"))?;
    file.sync_all().map_err(|e| format!("刷新临时文件失败：{e}"))?;
    drop(file);
    replace_existing(&temp, path)?;
    Ok(())
}

#[cfg(windows)]
fn replace_existing(temp: &Path, target: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
    let source: Vec<u16> = temp.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let destination: Vec<u16> = target.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let replaced = unsafe {
        MoveFileExW(source.as_ptr(), destination.as_ptr(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)
    };
    if replaced == 0 { return Err(format!("替换本地数据失败：{}", std::io::Error::last_os_error())); }
    Ok(())
}

#[cfg(not(windows))]
fn replace_existing(temp: &Path, target: &Path) -> Result<(), String> {
    fs::rename(temp, target).map_err(|e| format!("替换本地数据失败：{e}"))
}

#[tauri::command]
pub fn write_planner_data<R: Runtime>(app: AppHandle<R>, envelope: StorageEnvelope) -> Result<(), String> {
    if envelope.version != SCHEMA_VERSION || !envelope.data.is_object() {
        return Err("拒绝写入无效的计划数据。".into());
    }
    let path = data_path(&app)?;
    let backup = backup_path(&app)?;
    if path.exists() {
        fs::copy(&path, &backup).map_err(|e| format!("创建最近备份失败：{e}"))?;
    }
    let bytes = serde_json::to_vec_pretty(&envelope).map_err(|e| e.to_string())?;
    atomic_replace(&path, &bytes)
}

#[tauri::command]
pub fn read_json_file(path: String) -> Result<Value, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("读取导入文件失败：{e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("导入 JSON 无法解析：{e}"))
}

#[tauri::command]
pub fn write_json_file(path: String, data: Value) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(&data).map_err(|e| e.to_string())?;
    let target = PathBuf::from(path);
    atomic_replace(&target, &bytes)
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .invoke_handler(tauri::generate_handler![
            read_planner_data,
            write_planner_data,
            read_json_file,
            write_json_file
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
