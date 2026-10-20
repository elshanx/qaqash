import AppKit
import SystemConfiguration

let scripts = DispatchQueue(label: "qaqash.scripts")

extension NSAppleScript {
    func text() -> String? {
        var error: NSDictionary?
        let result = executeAndReturnError(&error)
        return error == nil ? result.stringValue ?? "" : nil
    }
}

func runScript(_ source: String) -> String? {
    NSAppleScript(source: source)?.text()
}

func appIsRunning(_ bundleId: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
}

func claudeAppIsFrontmost() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.anthropic.claudefordesktop"
}

func appBundleId(_ pid: Int32) -> String? {
    guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
    return app.bundleIdentifier
}

func parentOf(_ pid: Int32) -> Int32? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
}

func openApp(_ bundleId: String) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

@discardableResult
func run(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
}

func localHostName() -> String {
    SCDynamicStoreCopyLocalHostName(nil) as String? ?? ""
}

func readFile(_ path: String?) -> String? {
    guard let path, path.hasPrefix("/"),
          let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size <= 1_000_000 else { return nil }
    return try? String(contentsOfFile: path, encoding: .utf8)
}
