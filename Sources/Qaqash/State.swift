import SwiftUI

typealias JSON = [String: Any]

enum Mood { case idle, thinking, needs, done }
enum Tab { case home, sessions, settings }
enum Page { case prompt, home, sessions, settings }

struct HookEvent {
    var raw: JSON

    var name: String { raw["hook_event_name"] as? String ?? "" }
    var sessionId: String? { raw["session_id"] as? String }
    var cwd: String? { raw["cwd"] as? String }
    var transcriptPath: String? { raw["transcript_path"] as? String }
    var toolName: String? { raw["tool_name"] as? String }
    var input: JSON { raw["tool_input"] as? JSON ?? [:] }
    var message: String? { raw["message"] as? String }
    var pid: Int32? { (raw["qaqash_pid"] as? Int).map { Int32($0) } }
    var filePath: String? { input["file_path"] as? String }
}

struct Ask: Identifiable {
    var id: Int
    var kind: String
    var event: HookEvent
}

@MainActor @Observable final class AppState {
    var queue: [Ask] = []
    var step = 0
    var picks: [String: [String]] = [:]
    var askHunks: [Int: [Hunk]] = [:]
    var hovering = false
    var tab = Tab.home
    var lastStatus = "qaqash"
    var mood = Mood.idle
    var barHeight: CGFloat = 33
    var notch: CGFloat = 80
    var bumped = false
    var context: Double?
    var activity: Activity?
    var runs: [String: Run] = [:]
    var finished: Finished?
    var sessions: [Session] = []
    var track: Track?
    var trackSyncedAt = Date()
    var artwork: NSImage?
    var tint: Color?
    var vscode: VSCodeWindow?
    @ObservationIgnored var hit = CGSize.zero
    @ObservationIgnored var restTask: Task<Void, Never>?
    @ObservationIgnored var activityTask: Task<Void, Never>?

    var working: Bool { settings.editPanel && !(activity?.hunks.isEmpty ?? true) }

    var page: Page? {
        if !queue.isEmpty { return .prompt }
        if hovering {
            switch tab {
            case .home: return .home
            case .sessions: return .sessions
            case .settings: return .settings
            }
        }
        return working ? .home : nil
    }

    var open: Bool { page != nil }
    var showActivity: Bool { page == .home && working }
    var showTabs: Bool { queue.isEmpty && hovering }
    var contentWidth: CGFloat { showActivity ? 510 : 460 }
    var width: CGFloat { open ? contentWidth : 340 + (bumped ? 18 : 0) }
    var displayMood: Mood { queue.isEmpty ? mood : .needs }
    var musicMode: Bool { track?.playing == true && displayMood != .needs }

    var statusText: String {
        guard let first = queue.first else { return lastStatus }
        return first.kind == "pair" ? "Pairing" : projectOf(first.event)
    }

    func receive(_ event: HookEvent) {
        guard event.name != "PostToolUse" else { return withAnimation(.morph) { trackActivity(event) } }
        withAnimation(.morph) {
            lastStatus = describe(event)
            dropStale(event)
            trackSession(event)
            trackActivity(event)
            setMood(moodOf(event))
        }
        trackContext(event)
    }

    func setMood(_ next: Mood) {
        restTask?.cancel()
        mood = next
        guard displayMood == .done else { return }
        restTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.morph) { setMood(.idle) }
        }
    }

    func setHovering(_ inside: Bool) {
        withAnimation(.morph) {
            hovering = inside
            if !inside { tab = .home }
        }
        if inside { refreshVSCode() }
    }

    func bump() {
        guard !open else { return }
        withAnimation(.morph) { bumped = true }
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.morph) { bumped = false }
        }
    }
}

@MainActor let state = AppState()
