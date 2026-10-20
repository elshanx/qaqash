import Foundation

private let activities = [
    "Bash": "Running", "Read": "Reading", "Edit": "Editing", "Write": "Writing", "NotebookEdit": "Editing",
    "Grep": "Searching", "Glob": "Searching", "WebFetch": "Browsing", "WebSearch": "Searching",
    "Task": "Delegating", "Agent": "Delegating", "AskUserQuestion": "Asking", "TodoWrite": "Planning",
]

func describe(_ event: HookEvent) -> String {
    switch event.name {
    case "SessionStart": "Ready"
    case "SessionEnd": "Ended"
    case "UserPromptSubmit": "Thinking…"
    case "PreToolUse": activities[event.toolName ?? ""] ?? "Working…"
    case "Notification": event.message ?? "Needs you"
    case "PermissionRequest": "Needs you"
    case "Stop": "Done"
    default: event.name
    }
}

func moodOf(_ event: HookEvent) -> Mood {
    switch event.name {
    case "Notification": .needs
    case "Stop": .done
    default: .thinking
    }
}

func projectOf(_ event: HookEvent) -> String {
    if let project = event.cwd?.split(separator: "/").last, !project.isEmpty { return String(project) }
    if let id = event.sessionId, !id.isEmpty { return String(id.prefix(8)) }
    return "Claude"
}

func summarize(_ input: JSON) -> String {
    for key in ["command", "file_path", "url"] {
        if let value = input[key] { return "\(value)" }
    }
    return json(input, pretty: true)
}

func json(_ value: Any, pretty: Bool = false) -> String {
    String(decoding: jsonData(value, pretty: pretty), as: UTF8.self)
}

func jsonData(_ value: Any, pretty: Bool = false) -> Data {
    let options: JSONSerialization.WritingOptions = pretty ? [.withoutEscapingSlashes, .prettyPrinted, .sortedKeys] : [.withoutEscapingSlashes]
    return (try? JSONSerialization.data(withJSONObject: value, options: options)) ?? Data()
}
