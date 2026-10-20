use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter, LogicalPosition, LogicalSize, WebviewWindow};

pub const CANVAS: (f64, f64) = (540.0, 560.0);
static HIT_AREA: Mutex<(f64, f64)> = Mutex::new((0.0, 0.0));

#[tauri::command]
pub fn set_hit_area(width: f64, height: f64) {
    *HIT_AREA.lock().unwrap() = (width, height);
}

pub fn place(window: &WebviewWindow, width: f64, height: f64) -> tauri::Result<()> {
    let monitor = window.primary_monitor()?.unwrap();
    let screen_width = monitor.size().width as f64 / monitor.scale_factor();
    window.set_size(LogicalSize::new(width, height))?;
    window.set_position(LogicalPosition::new((screen_width - width) / 2.0, 0.0))
}

#[tauri::command]
pub fn menu_bar_height(window: WebviewWindow) -> Result<f64, String> {
    let monitor = window.primary_monitor().map_err(|e| e.to_string())?.ok_or("no monitor")?;
    Ok(monitor.work_area().position.y as f64 / monitor.scale_factor())
}

pub fn watch_hover(app: AppHandle, window: WebviewWindow) {
    let mut last = None;
    loop {
        thread::sleep(Duration::from_millis(30));
        let (Ok(cursor), Ok(origin), Ok(scale)) = (app.cursor_position(), window.outer_position(), window.scale_factor()) else {
            continue;
        };
        let x = (cursor.x - origin.x as f64) / scale;
        let y = (cursor.y - origin.y as f64) / scale;
        let (width, height) = *HIT_AREA.lock().unwrap();
        let inside = (x - CANVAS.0 / 2.0).abs() < width / 2.0 && y >= 0.0 && y < height;
        let pointer = inside.then(|| (x.round() as i32, y.round() as i32));
        if pointer.is_some() != last.is_some() {
            let _ = window.set_ignore_cursor_events(!inside);
        }
        if pointer != last {
            last = pointer;
            let _ = app.emit("hover", pointer);
        }
    }
}
