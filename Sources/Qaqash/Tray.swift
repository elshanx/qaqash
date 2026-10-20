import AppKit

@MainActor final class Tray: NSObject {
    static let shared = Tray()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override private init() {
        super.init()
        item.button?.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 5, width: 3.5, height: 8), xRadius: 1.75, yRadius: 1.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 5, width: 3.5, height: 8), xRadius: 1.75, yRadius: 1.75).fill()
            return true
        }
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(withTitle: "Pair iPhone…", action: #selector(pair), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Qaqash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
    }

    func update() {
        item.isVisible = settings.menuBarIcon
    }

    @objc private func pair() {
        PairWindow.open()
    }
}
