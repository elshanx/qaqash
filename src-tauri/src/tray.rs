use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{App, AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

pub fn create(app: &App) -> tauri::Result<()> {
    let pair = MenuItem::with_id(app, "pair", "Pair iPhone…", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Qaqash", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&pair, &quit])?;
    TrayIconBuilder::with_id("main")
        .icon(Image::from_bytes(include_bytes!("../icons/tray.png"))?)
        .icon_as_template(true)
        .menu(&menu)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "pair" => open_pairing(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

#[tauri::command]
pub fn set_tray_visible(app: AppHandle, visible: bool) {
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_visible(visible);
    }
}

#[tauri::command]
pub fn pair_iphone(app: AppHandle) {
    open_pairing(&app);
}

#[tauri::command]
pub fn quit(app: AppHandle) {
    app.exit(0);
}

fn open_pairing(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("pair") {
        let _ = window.set_focus();
        return;
    }
    let window = WebviewWindowBuilder::new(app, "pair", WebviewUrl::App("pair.html".into()))
        .title("Pair iPhone")
        .inner_size(360.0, 470.0)
        .resizable(false)
        .center()
        .build();
    if let Ok(window) = window {
        let _ = window.set_focus();
    }
}
