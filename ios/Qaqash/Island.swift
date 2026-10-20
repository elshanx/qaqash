import ActivityKit
import Foundation
import LocalAuthentication

struct Session: Identifiable {
    var id: String
    var project: String
    var status: String
    var mood: Mood
}

private let activities = [
    "Bash": "Running", "Read": "Reading", "Edit": "Editing", "Write": "Writing", "NotebookEdit": "Editing",
    "Grep": "Searching", "Glob": "Searching", "WebFetch": "Browsing", "WebSearch": "Searching",
    "Task": "Delegating", "Agent": "Delegating", "AskUserQuestion": "Asking", "TodoWrite": "Planning",
]

func projectOf(_ event: [String: Any]) -> String {
    (event["cwd"] as? String)?.split(separator: "/").last.map(String.init) ?? "Claude"
}

private func describe(_ event: [String: Any]) -> (String, Mood) {
    switch event["hook_event_name"] as? String {
    case "UserPromptSubmit": ("Thinking…", .thinking)
    case "PreToolUse": (activities[event["tool_name"] as? String ?? ""] ?? "Working…", .thinking)
    case "Notification": (event["message"] as? String ?? "Needs you", .needs)
    case "Stop": ("Done", .done)
    case "SessionStart": ("Ready", .idle)
    default: ("Working…", .thinking)
    }
}

@MainActor
final class Island: ObservableObject {
    @Published var pairing = Pairing.load()
    @Published var asks: [Ask] = []
    @Published var sessions: [Session] = []
    @Published var connected = false

    private var seq = 0
    private var polling: Task<Void, Never>?
    private var activity: Activity<IslandAttributes>?

    var mood: Mood {
        if !asks.isEmpty { return .needs }
        return sessions.first?.mood ?? .idle
    }

    func pair(_ pairing: Pairing) {
        pairing.save()
        self.pairing = pairing
        seq = 0
        start()
    }

    func unpair() {
        polling?.cancel()
        Pairing.forget()
        pairing = nil
        asks = []
        sessions = []
        connected = false
        endActivity()
    }

    func start() {
        guard let pairing, polling == nil else { return }
        let link = Link(pairing)
        polling = Task {
            while !Task.isCancelled {
                do {
                    if seq == 0 {
                        load(try await link.json("/state"))
                    } else {
                        apply(try await link.json("/events?after=\(seq)"))
                    }
                    connected = true
                } catch {
                    connected = false
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    private func load(_ state: [String: Any]) {
        seq = state["seq"] as? Int ?? 0
        asks = (state["asks"] as? [[String: Any]] ?? []).compactMap(Ask.init)
        sessions = []
        for event in state["sessions"] as? [[String: Any]] ?? [] { track(event) }
        if seq == 0 { seq = -1 }
        refreshActivity()
    }

    private func apply(_ batch: [String: Any]) {
        if batch["reset"] as? Bool == true {
            seq = 0
            return
        }
        for event in batch["events"] as? [[String: Any]] ?? [] {
            let data = event["data"] as? [String: Any] ?? [:]
            switch event["kind"] as? String {
            case "ask": if let ask = Ask(data), !asks.contains(ask) { asks.append(ask) }
            case "resolved": asks.removeAll { $0.id == data["id"] as? Int }
            case "status": track(data)
            default: break
            }
        }
        seq = max(seq, batch["seq"] as? Int ?? seq)
        refreshActivity()
    }

    private func track(_ event: [String: Any]) {
        guard let id = event["session_id"] as? String else { return }
        sessions.removeAll { $0.id == id }
        if event["hook_event_name"] as? String == "SessionEnd" { return }
        let (status, mood) = describe(event)
        sessions.insert(Session(id: id, project: projectOf(event), status: status, mood: mood), at: 0)
    }

    func decide(_ ask: Ask, answer: Any) async {
        guard let pairing else { return }
        if answer as? Bool == true, !(await confirm()) { return }
        try? await Link(pairing).decide(ask.id, answer: answer)
        asks.removeAll { $0.id == ask.id }
        refreshActivity()
    }

    private func confirm() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Allow Claude to continue")) ?? false
    }

    private var activityState: IslandAttributes.ContentState {
        if let ask = asks.first {
            let status = ask.kind == "question" ? "Has a question" : "Wants to use \(ask.event["tool_name"] as? String ?? "a tool")"
            return .init(mood: .needs, project: projectOf(ask.event), status: status, working: sessions.count)
        }
        let latest = sessions.first
        return .init(mood: mood, project: latest?.project ?? "Qaqash", status: latest?.status ?? "Idle", working: sessions.count)
    }

    private func refreshActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: activityState, staleDate: nil)
        if sessions.isEmpty && asks.isEmpty {
            endActivity()
        } else if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(attributes: IslandAttributes(), content: content)
        }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
