import AppKit
import SwiftUI

private final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class HostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class IslandWindow {
    static let canvas = CGSize(width: 540, height: 560)
    static let shared = IslandWindow()
    private let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var timer: Timer?

    func show() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(25)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        let hosting = HostingView(rootView: IslandView())
        hosting.sizingOptions = []
        panel.contentView = hosting
        place()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchHover() }
        }
    }

    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        state.barHeight = menuBar > 0 ? menuBar : 33
        panel.setFrame(NSRect(x: screen.frame.midX - Self.canvas.width / 2, y: screen.frame.maxY - Self.canvas.height, width: Self.canvas.width, height: Self.canvas.height), display: true)
    }

    private func watchHover() {
        let mouse = NSEvent.mouseLocation
        let x = mouse.x - panel.frame.minX
        let y = panel.frame.maxY - mouse.y
        let inside = abs(x - Self.canvas.width / 2) < state.hit.width / 2 && y >= 0 && y < state.hit.height
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if state.hovering != inside { state.setHovering(inside) }
    }
}
