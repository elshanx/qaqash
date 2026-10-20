use std::ffi::{c_char, CStr, CString};
use std::process::Command;
use objc2::msg_send;
use objc2::rc::autoreleasepool;
use objc2::runtime::{AnyClass, AnyObject};

pub fn claude_app_is_frontmost() -> bool {
    autoreleasepool(|_| unsafe {
        let Some(workspace_class) = AnyClass::get(c"NSWorkspace") else { return false };
        let workspace: *mut AnyObject = msg_send![workspace_class, sharedWorkspace];
        let app: *mut AnyObject = msg_send![&*workspace, frontmostApplication];
        if app.is_null() {
            return false;
        }
        let bundle_id: *mut AnyObject = msg_send![&*app, bundleIdentifier];
        if bundle_id.is_null() {
            return false;
        }
        let utf8: *const c_char = msg_send![&*bundle_id, UTF8String];
        CStr::from_ptr(utf8).to_bytes() == b"com.anthropic.claudefordesktop"
    })
}

pub fn app_is_running(bundle_id: &CStr) -> bool {
    autoreleasepool(|_| unsafe {
        let Some(app_class) = AnyClass::get(c"NSRunningApplication") else { return false };
        let Some(string_class) = AnyClass::get(c"NSString") else { return false };
        let id: *mut AnyObject = msg_send![string_class, stringWithUTF8String: bundle_id.as_ptr()];
        let apps: *mut AnyObject = msg_send![app_class, runningApplicationsWithBundleIdentifier: id];
        let count: usize = msg_send![&*apps, count];
        count > 0
    })
}

pub fn app_bundle_id(pid: i32) -> Option<String> {
    autoreleasepool(|_| unsafe {
        let app_class = AnyClass::get(c"NSRunningApplication")?;
        let app: *mut AnyObject = msg_send![app_class, runningApplicationWithProcessIdentifier: pid];
        if app.is_null() {
            return None;
        }
        let policy: isize = msg_send![&*app, activationPolicy];
        let bundle_id: *mut AnyObject = msg_send![&*app, bundleIdentifier];
        if policy != 0 || bundle_id.is_null() {
            return None;
        }
        let utf8: *const c_char = msg_send![&*bundle_id, UTF8String];
        Some(CStr::from_ptr(utf8).to_string_lossy().into_owned())
    })
}

pub fn osascript(script: &str, args: &[&str]) -> Option<String> {
    let output = Command::new("osascript").arg("-e").arg(script).args(args).output().ok()?;
    output.status.success().then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub struct AppleScript(*mut AnyObject);

impl AppleScript {
    pub fn new(source: &str) -> Option<Self> {
        let source = CString::new(source).ok()?;
        unsafe {
            let string_class = AnyClass::get(c"NSString")?;
            let script_class = AnyClass::get(c"NSAppleScript")?;
            let text: *mut AnyObject = msg_send![string_class, stringWithUTF8String: source.as_ptr()];
            let script: *mut AnyObject = msg_send![script_class, alloc];
            let script: *mut AnyObject = msg_send![script, initWithSource: text];
            (!script.is_null()).then_some(Self(script))
        }
    }

    pub fn run(&self) -> Option<String> {
        autoreleasepool(|_| unsafe {
            let mut error: *mut AnyObject = std::ptr::null_mut();
            let result: *mut AnyObject = msg_send![&*self.0, executeAndReturnError: &mut error];
            if result.is_null() {
                return None;
            }
            let text: *mut AnyObject = msg_send![&*result, stringValue];
            if text.is_null() {
                return Some(String::new());
            }
            let utf8: *const c_char = msg_send![&*text, UTF8String];
            Some(CStr::from_ptr(utf8).to_string_lossy().into_owned())
        })
    }
}
