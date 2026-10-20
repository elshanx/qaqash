mod hooks;
mod macos;
mod music;
mod phone;
mod sessions;
mod tray;
mod vscode;
mod window;

use std::thread;
use tauri::{ActivationPolicy, Manager};

fn main() {
    tauri::Builder::default()
        .manage(hooks::Pending::default())
        .invoke_handler(tauri::generate_handler![window::set_hit_area, window::menu_bar_height, hooks::decide, hooks::set_settings, tray::set_tray_visible, tray::pair_iphone, tray::quit, hooks::forget, music::music_control, music::music_artwork, sessions::open_session, sessions::session_app, sessions::read_file, sessions::context_used, vscode::vscode_window, vscode::open_vscode, sessions::open_in_vscode, phone::pairing_code, phone::pairing_text])
        .setup(|app| {
            app.set_activation_policy(ActivationPolicy::Accessory);
            tray::create(app)?;

            let window = app.get_webview_window("main").unwrap();
            window::place(&window, window::CANVAS.0, window::CANVAS.1)?;
            window.set_ignore_cursor_events(true)?;

            let ns_window = window.ns_window()? as *const objc2::runtime::AnyObject;
            unsafe {
                let _: () = objc2::msg_send![&*ns_window, setLevel: 25isize];
                let _: () = objc2::msg_send![&*ns_window, setAcceptsMouseMovedEvents: true];
            }

            window.show()?;

            let handle = app.handle().clone();
            let music_handle = handle.clone();
            let hover_handle = handle.clone();
            let phone_handle = handle.clone();
            thread::spawn(move || hooks::serve(handle));
            thread::spawn(move || phone::serve(phone_handle));
            thread::spawn(move || music::watch_music(music_handle));
            thread::spawn(move || window::watch_hover(hover_handle, window));
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running qaqash");
}
