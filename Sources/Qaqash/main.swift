import AppKit

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    IslandWindow.shared.show()
    Tray.shared.update()
    Hooks.start()
    phone.start()
    Music.start()
    state.startSessions()
}
NSApplication.shared.run()
