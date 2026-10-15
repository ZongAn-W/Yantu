use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, Manager, Runtime};

mod storage;
use storage::{atomic_replace, read_slot, slot_path, write_slot, ReadResult, StorageEnvelope};
#[derive(Default)]
struct StorageLock(Mutex<()>);

fn data_dir<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let path = app.path().app_data_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&path).map_err(|e| format!("创建本地数据目录失败：{e}"))?;
    Ok(path)
}

#[tauri::command]
fn read_planner_data<R: Runtime>(app: AppHandle<R>, state: tauri::State<'_, StorageLock>, key: String) -> Result<ReadResult, String> {
    let _guard = state.0.lock().map_err(|e| e.to_string())?;
    Ok(read_slot(&slot_path(&data_dir(&app)?, &key)?))
}

#[tauri::command]
fn write_planner_data<R: Runtime>(app: AppHandle<R>, state: tauri::State<'_, StorageLock>, key: String, envelope: StorageEnvelope, recovery: bool) -> Result<(), String> {
    let _guard = state.0.lock().map_err(|e| e.to_string())?;
    write_slot(&slot_path(&data_dir(&app)?, &key)?, &envelope, recovery)
}

#[tauri::command]
fn read_json_file(path: String) -> Result<Value, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("读取导入文件失败：{e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("导入 JSON 无法解析：{e}"))
}

#[tauri::command]
fn write_json_file(path: String, data: Value) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(&data).map_err(|e| e.to_string())?;
    let target = PathBuf::from(path);
    atomic_replace(&target, &bytes)
}

pub fn run() {
    tauri::Builder::default()
        .manage(StorageLock::default())
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .invoke_handler(tauri::generate_handler![
            read_planner_data,
            write_planner_data,
            read_json_file,
            write_json_file
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
