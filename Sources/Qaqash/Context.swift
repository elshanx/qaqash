import SwiftUI

func contextShare(_ used: Int) -> Double {
    min(Double(used) / Double(used > 200_000 ? 1_000_000 : 200_000), 1)
}

func contextUsed(_ path: String) -> Int? {
    let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path + "/"
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard path.hasPrefix("/"), url.path.hasPrefix(projects), url.pathExtension == "jsonl", let file = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? file.close() }
    let length = (try? file.seekToEnd()) ?? 0
    try? file.seek(toOffset: length > 512 * 1024 ? length - 512 * 1024 : 0)
    let text = String(decoding: file.readDataToEndOfFile(), as: UTF8.self)
    for line in text.split(separator: "\n").reversed() {
        guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON,
              entry["type"] as? String == "assistant", entry["isSidechain"] as? Bool != true,
              let usage = (entry["message"] as? JSON)?["usage"] as? JSON else { continue }
        return ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0] as? Int }.reduce(0, +)
    }
    return nil
}

extension AppState {
    func trackContext(_ event: HookEvent) {
        guard let path = event.transcriptPath, ["UserPromptSubmit", "PreToolUse", "Stop"].contains(event.name) else { return }
        DispatchQueue.global().async {
            guard let used = contextUsed(path) else { return }
            DispatchQueue.main.async {
                if let index = self.sessions.firstIndex(where: { $0.id == event.sessionId }) { self.sessions[index].context = used }
                withAnimation(.easeOut(duration: 0.3)) { self.context = contextShare(used) }
            }
        }
    }
}

struct ContextRing: View {
    var diameter: CGFloat
    var line: CGFloat

    var body: some View {
        if let share = state.context {
            let color = share > 0.95 ? Color.qRed : share > 0.8 ? Color.qOrange : .white.opacity(0.7)
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: line)
                Circle().trim(from: 0, to: share).stroke(color, lineWidth: line).rotationEffect(.degrees(-90))
            }
            .frame(width: diameter - line, height: diameter - line)
            .allowsHitTesting(false)
        }
    }
}
