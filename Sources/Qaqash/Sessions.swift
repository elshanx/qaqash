import SwiftUI

struct Session: Identifiable {
    var id: String
    var name: String
    var state: String
    var mood: Mood
    var seen: Date
    var pid: Int32?
    var cwd: String?
    var app: String?
    var lastFile: String?
    var context: Int?
}

func sessionApp(_ pid: Int32) -> String? {
    var current = pid
    while current > 1 {
        if let bundleId = appBundleId(current) { return bundleId }
        guard let parent = parentOf(current) else { return nil }
        current = parent
    }
    return nil
}

func openSession(_ pid: Int32, cwd: String?) {
    DispatchQueue.global().async {
        guard let app = sessionApp(pid) else { return }
        openApp(app, folder: app == vscodeId ? cwd : nil)
    }
}

extension AppState {
    func trackSession(_ event: HookEvent) {
        guard let id = event.sessionId, event.transcriptPath != nil else { return }
        let index = sessions.firstIndex { $0.id == id }
        if event.name == "SessionEnd" {
            if let index { sessions.remove(at: index) }
            return
        }
        let known = index.map { sessions[$0] }
        let pid = event.pid ?? known?.pid
        let session = Session(id: id, name: known?.name ?? projectOf(event), state: describe(event), mood: moodOf(event), seen: Date(), pid: pid, cwd: event.cwd ?? known?.cwd,
                              app: known?.app, lastFile: changesFiles(event.toolName) ? fileOf(event) : known?.lastFile, context: known?.context)
        if let index { sessions[index] = session } else { sessions.append(session) }
        guard let pid, pid != known?.pid else { return }
        DispatchQueue.global().async {
            guard let app = sessionApp(pid) else { return }
            DispatchQueue.main.async {
                if let index = self.sessions.firstIndex(where: { $0.id == id }) { self.sessions[index].app = app }
            }
        }
    }

    func startSessions() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let cutoff = Date().addingTimeInterval(-30 * 60)
                withAnimation(.morph) { self.sessions.removeAll { $0.seen < cutoff } }
            }
        }
    }
}

struct SessionList: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(state.sessions) { SessionRow(session: $0) }
        }
        .padding(.top, 2)
    }
}

private struct SessionRow: View {
    var session: Session
    @State private var hovering = false

    var body: some View {
        let info = [session.state, session.lastFile, session.app == vscodeId ? "VS Code" : nil, session.context.map { "\(Int((contextShare($0) * 100).rounded()))%" }]
            .compactMap { $0 }.joined(separator: " · ")
        let clickable = session.pid != nil
        Button {
            guard let pid = session.pid else { return }
            openSession(pid, cwd: session.cwd)
        } label: {
            HStack(spacing: 8) {
                Dot(mood: session.mood)
                Text(session.name)
                Spacer(minLength: 8)
                Text(info).opacity(0.55).lineLimit(1).offset(x: clickable && hovering ? -16 : 0)
            }
            .overlay(alignment: .trailing) {
                Text("↗").font(.system(size: 11)).opacity(clickable && hovering ? 0.55 : 0).offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(clickable && hovering ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, -10)
            .padding(.vertical, -5)
        }
        .buttonStyle(Press(scale: 1))
        .disabled(!clickable)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct Dot: View {
    var mood: Mood

    var body: some View {
        let color: Color = switch mood {
        case .thinking: .qBlue
        case .needs: .qOrange
        case .done: .qGreen
        case .idle: Color(hex: 0x8e8e93)
        }
        Circle().fill(color).frame(width: 6, height: 6)
            .phaseAnimator([1, mood == .thinking ? 1.15 : 1]) { $0.scaleEffect($1) } animation: { _ in .easeInOut(duration: 0.7) }
    }
}
