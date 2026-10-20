import SwiftUI

struct Run {
    var steps: [String] = []
    var done = false
    var command: String?
    var output: [String] = []
}

struct Activity {
    var id = UUID()
    var event: HookEvent
    var hunks: [Hunk]
}

func readHunks(_ event: HookEvent) -> [Hunk] {
    hunksOf(event, readFile(event.filePath))
}

private func outputOf(_ event: HookEvent) -> [String] {
    let response = event.raw["tool_response"] as? JSON ?? [:]
    let text = [response["stdout"], response["stderr"]].compactMap { $0 as? String }.joined(separator: "\n")
    return Array(text.split(separator: "\n").map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(5))
}

private func nextRun(_ event: HookEvent, _ run: Run) -> Run? {
    var run = run
    switch event.name {
    case "PreToolUse":
        guard let tool = event.toolName, tool != "AskUserQuestion" else { return nil }
        if run.steps.last != tool { run.steps = Array((run.steps + [tool]).suffix(6)) }
        run.done = false
    case "PostToolUse":
        guard event.toolName == "Bash" else { return nil }
        run.command = event.input["command"] as? String
        run.output = outputOf(event)
    case "Stop":
        run.done = true
    default:
        return nil
    }
    return run
}

extension AppState {
    func trackActivity(_ event: HookEvent) {
        let id = event.sessionId ?? ""
        if event.name == "UserPromptSubmit" || event.name == "SessionEnd" {
            runs[id] = nil
            return
        }
        guard let run = nextRun(event, runs[id] ?? Run()) else { return }
        runs[id] = run
        if changesFiles(event.toolName) { activity = Activity(event: event, hunks: readHunks(event)) }
        if let activity, activity.event.sessionId == id, !activity.hunks.isEmpty { linger() }
    }

    private func linger() {
        activityTask?.cancel()
        activityTask = Task {
            repeat { try? await Task.sleep(for: .seconds(6)) } while hovering && !Task.isCancelled
            guard !Task.isCancelled else { return }
            withAnimation(.morph) { activity = nil }
        }
        refreshVSCode()
    }
}

private func openInVSCode(_ event: HookEvent) {
    guard let path = event.filePath, path.hasPrefix("/") else { return }
    let edits = event.input["edits"] as? [JSON] ?? [event.input]
    let needles = edits.flatMap { [$0["new_string"] as? String ?? "", $0["old_string"] as? String ?? ""] }.filter { !$0.isEmpty }
    let text = readFile(path) ?? ""
    let line = needles.lazy.compactMap { text.range(of: $0) }.first.map { text[..<$0.lowerBound].filter { $0 == "\n" }.count + 1 } ?? 1
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-_.~")
    guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: "vscode://file\(encoded):\(line)") else { return }
    NSWorkspace.shared.open(url)
}

private let toolIcons = [
    "Read": "book", "Edit": "pencil", "MultiEdit": "pencil", "Write": "pencil", "NotebookEdit": "pencil",
    "Bash": "terminal", "Grep": "magnifyingglass", "Glob": "magnifyingglass", "WebFetch": "globe", "WebSearch": "globe",
]

struct ActivityView: View {
    var activity: Activity

    var body: some View {
        let run = state.runs[activity.event.sessionId ?? ""] ?? Run()
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Avatar()
                Text(projectOf(activity.event)).font(.system(size: 15, weight: .semibold)).lineLimit(1).padding(.top, 14)
                Text("Claude Code").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(run.steps.enumerated()), id: \.offset) { index, name in
                        StepRow(name: name, running: index == run.steps.count - 1 && !run.done)
                    }
                    if run.done { StepRow(name: "Done", running: false) }
                }
                .padding(.top, 14)
            }
            .frame(width: 104, alignment: .leading)
            .padding(.top, 4)
            .padding(.leading, 2)
            code(run)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func code(_ run: Run) -> some View {
        let unsaved = !run.done && changesFiles(run.steps.last)
        let name = fileOf(activity.event)
        let language = name.contains(".") ? String(name.split(separator: ".").last!.prefix(2)).uppercased() : ""
        let path = activity.event.filePath ?? ""
        let cwd = activity.event.cwd ?? ""
        let relative = !cwd.isEmpty && path.hasPrefix(cwd + "/") ? String(path.dropFirst(cwd.count + 1)) : path
        return Button { openInVSCode(activity.event) } label: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if !language.isEmpty {
                        Text(language).font(.system(size: 8, weight: .bold)).padding(.horizontal, 3).padding(.vertical, 1).background(Color(hex: 0x3178c6), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(name).foregroundStyle(.white.opacity(0.85))
                    if unsaved { Circle().fill(Color.qOrange).frame(width: 6, height: 6) }
                    Spacer(minLength: 6)
                    Text(relative).foregroundStyle(.white.opacity(0.35)).lineLimit(1).truncationMode(.head)
                }
                .font(mono)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.field)
                DiffView(hunks: activity.hunks, typing: activity.id, height: run.command == nil ? 280 : 200)
                if let command = run.command { Terminal(command: command, output: run.output).transition(.rise) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(hex: 0x121214))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(CodeStyle())
    }
}

private struct CodeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Outlined(label: configuration.label)
    }

    struct Outlined<Label: View>: View {
        var label: Label
        @State private var hovering = false

        var body: some View {
            label
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(hovering ? 0.18 : 0), lineWidth: 1) }
                .onHover { hovering = $0 }
        }
    }
}

private struct Terminal: View {
    var command: String
    var output: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("$ \(command)").foregroundStyle(.white.opacity(0.85))
            ForEach(Array(output.enumerated()), id: \.offset) { Text($1).foregroundStyle(color($1)) }
        }
        .font(mono)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.field)
    }

    private func color(_ line: String) -> Color {
        let lower = line.lowercased()
        if ["fail", "error", "✗"].contains(where: lower.contains) { return .qRed }
        if ["pass", "✓", "✔"].contains(where: lower.contains) { return .qGreen }
        return .white.opacity(0.55)
    }
}

private struct StepRow: View {
    var name: String
    var running: Bool

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 14, height: 14)
            Text(name.hasPrefix("mcp__") ? name.components(separatedBy: "__").last ?? name : name).lineLimit(1)
        }
        .font(.system(size: 13, weight: running ? .semibold : .regular))
        .foregroundStyle(.white.opacity(running ? 1 : name == "Done" ? 0.85 : 0.45))
    }

    @ViewBuilder private var icon: some View {
        if running {
            Spinner()
        } else if name == "Done" {
            Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black).frame(width: 14, height: 14).background(Color.qGreen, in: Circle())
        } else {
            Image(systemName: toolIcons[name] ?? "circle").font(.system(size: 11, weight: .medium))
        }
    }
}

private struct Spinner: View {
    var body: some View {
        Circle().stroke(.white.opacity(0.25), lineWidth: 2)
            .overlay {
                Circle().trim(from: 0, to: 0.25).stroke(.white, lineWidth: 2)
                    .keyframeAnimator(initialValue: 0.0, repeating: true) { $0.rotationEffect(.degrees($1)) } keyframes: { _ in LinearKeyframe(360, duration: 0.8) }
            }
            .padding(1)
    }
}
