import SwiftUI

let vscodeId = "com.microsoft.VSCode"
private let frontWindow = NSAppleScript(source: #"tell application "System Events" to tell process "Code" to get name of front window"#)

struct VSCodeWindow {
    var file: String
    var project: String

    init(title: String) {
        let parts = (title.hasPrefix("● ") ? String(title.dropFirst(2)) : title).components(separatedBy: " — ")
        file = parts.count > 1 ? parts[0] : ""
        project = parts.count > 1 ? parts[1] : parts[0]
    }
}

extension AppState {
    func refreshVSCode() {
        scripts.async {
            let title = appIsRunning(vscodeId) ? frontWindow?.text() : nil
            DispatchQueue.main.async { self.vscode = title.map(VSCodeWindow.init) }
        }
    }

    var vscodeLabel: (title: String, sub: String) {
        guard let vscode else { return ("VS Code", "Not open") }
        return vscode.file.isEmpty ? (vscode.project, "VS Code") : (vscode.file, "\(vscode.project) · VS Code")
    }
}

struct CodeIcon: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hex: 0x2b9af3), Color(hex: 0x0d5ea8)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: size / 4))
    }
}

struct VSCodeCard: View {
    var body: some View {
        let label = state.vscodeLabel
        Button { openApp(vscodeId) } label: {
            HStack(spacing: 14) {
                CodeIcon(size: 56).shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.title).font(.system(size: 15, weight: .semibold))
                    Text(label.sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(Source())
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        .padding(.top, 14)
    }
}

struct MiniVSCode: View {
    var body: some View {
        let label = state.vscodeLabel
        Button { openApp(vscodeId) } label: {
            HStack(spacing: 10) {
                CodeIcon(size: 26)
                Text("\(label.title) · \(label.sub)").font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
        }
        .buttonStyle(Source())
        .padding(.top, 8)
    }
}
