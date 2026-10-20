import SwiftUI

struct DiffLine: Equatable {
    enum Kind { case add, del, same }
    var kind: Kind
    var text: String
}

struct Hunk: Equatable {
    var start: Int
    var lines: [DiffLine]
}

private let maxLines = 400
private let context = 2

private func linesOf(_ text: String) -> [String] {
    text.isEmpty ? [] : Array(text.components(separatedBy: "\n").prefix(maxLines))
}

func diffLines(_ before: String, _ after: String) -> [DiffLine] {
    let a = linesOf(before)
    let b = linesOf(after)
    var common = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            common[i][j] = a[i] == b[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
        }
    }
    var lines: [DiffLine] = []
    var i = 0
    var j = 0
    while i < a.count || j < b.count {
        if i < a.count && j < b.count && a[i] == b[j] {
            lines.append(DiffLine(kind: .same, text: a[i]))
            i += 1
            j += 1
        } else if i < a.count && (j == b.count || common[i + 1][j] >= common[i][j + 1]) {
            lines.append(DiffLine(kind: .del, text: a[i]))
            i += 1
        } else {
            lines.append(DiffLine(kind: .add, text: b[j]))
            j += 1
        }
    }
    return lines
}

private func trim(_ lines: [DiffLine], _ start: Int) -> Hunk {
    guard let first = lines.firstIndex(where: { $0.kind != .same }), let last = lines.lastIndex(where: { $0.kind != .same }) else {
        return Hunk(start: start, lines: Array(lines.prefix(context * 2 + 1)))
    }
    let from = max(0, first - context)
    return Hunk(start: start == 0 ? 0 : start + from, lines: Array(lines[from..<min(lines.count, last + context + 1)]))
}

private func index(of needle: String, in text: NSString) -> Int {
    if needle.isEmpty { return 0 }
    let found = text.range(of: needle)
    return found.location == NSNotFound ? -1 : found.location
}

private func lineStartBefore(_ text: NSString, _ index: Int) -> Int {
    var at = index
    var n = 0
    while n <= context && at > 0 {
        let found = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: at))
        at = found.location == NSNotFound ? -1 : found.location
        n += 1
    }
    return at <= 0 ? 0 : at + 1
}

private func lineEndAfter(_ text: NSString, _ index: Int) -> Int {
    var at = index
    for n in 0...context {
        let from = n == 0 ? at : at + 1
        let found = text.range(of: "\n", range: NSRange(location: from, length: text.length - from))
        if found.location == NSNotFound { return text.length }
        at = found.location
    }
    return at
}

private func editHunk(_ text: String?, _ before: String, _ after: String) -> Hunk {
    guard let text, !text.isEmpty else { return trim(diffLines(before, after), 0) }
    let source = text as NSString
    let pending = index(of: before, in: source)
    let applied = pending < 0 ? index(of: after, in: source) : -1
    if pending < 0 && applied < 0 { return trim(diffLines(before, after), 0) }
    let at = pending >= 0 ? pending : applied
    let found = (pending >= 0 ? before : after) as NSString
    let from = lineStartBefore(source, at)
    let window = source.substring(with: NSRange(location: from, length: lineEndAfter(source, at + found.length) - from)) as NSString
    let offset = at - from
    let swapped = window.substring(to: offset) + (pending >= 0 ? after : before) + window.substring(from: offset + found.length)
    let start = source.substring(to: from).components(separatedBy: "\n").count
    return pending >= 0 ? trim(diffLines(window as String, swapped), start) : trim(diffLines(swapped, window as String), start)
}

private func multiEditHunks(_ text: String?, _ edits: [JSON]) -> [Hunk] {
    var current = text
    return edits.map { edit in
        let before = edit["old_string"] as? String ?? ""
        let after = edit["new_string"] as? String ?? ""
        let hunk = editHunk(current, before, after)
        if let source = current as NSString?, case let at = index(of: before, in: source), at >= 0 {
            current = source.replacingCharacters(in: NSRange(location: at, length: (before as NSString).length), with: after)
        }
        return hunk
    }
}

func hunksOf(_ event: HookEvent, _ text: String?) -> [Hunk] {
    let input = event.input
    switch event.toolName {
    case "Edit": return [editHunk(text, input["old_string"] as? String ?? "", input["new_string"] as? String ?? "")]
    case "MultiEdit": return multiEditHunks(text, input["edits"] as? [JSON] ?? [])
    case "Write": return [trim(diffLines(text ?? "", input["content"] as? String ?? ""), 1)]
    default: return []
    }
}

func changesFiles(_ toolName: String?) -> Bool {
    ["Edit", "MultiEdit", "Write"].contains(toolName ?? "")
}

func fileOf(_ event: HookEvent) -> String {
    (event.filePath ?? "").split(separator: "/").last.map(String.init) ?? ""
}

private let tokens = try! NSRegularExpression(pattern: #"(//.*)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`[^`]*`)|\b(import|from|export|default|function|const|let|var|return|if|else|for|while|of|in|new|class|extends|type|interface|async|await|true|false|null|undefined|pub|fn|use|mut|impl|struct|enum|match|self)\b|\b(\d[\d_.]*)\b|\b([A-Z]\w*)\b"#)
private let tokenColors = [Color.white.opacity(0.35), Color(hex: 0xc3e88d), Color(hex: 0xc792ea), Color(hex: 0xf78c6c), Color(hex: 0xffcb6b)]

func highlight(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    for match in tokens.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
        guard let group = (1...5).first(where: { match.range(at: $0).location != NSNotFound }),
              let range = Range(match.range, in: text), let styled = Range(range, in: result) else { continue }
        result[styled].foregroundColor = tokenColors[group - 1]
        if group == 1 { result[styled].font = mono.italic() }
    }
    return result
}

private struct Row: Identifiable {
    var id: Int
    var kind: DiffLine.Kind?
    var number = ""
    var text = AttributedString()
    var length = 0
    var delay: Double = 0
    var duration: Double = 0
    var caret = false
}

private func rows(_ hunks: [Hunk]) -> (rows: [Row], numbered: Bool, total: Double) {
    var rows: [Row] = []
    var delay = 0.0
    for (index, hunk) in hunks.enumerated() {
        if index > 0 { rows.append(Row(id: rows.count)) }
        var oldLine = hunk.start
        var newLine = hunk.start
        for line in hunk.lines {
            let number = line.kind == .add ? newLine : oldLine
            if line.kind == .add { newLine += 1 } else { oldLine += 1 }
            if line.kind == .same { newLine += 1 }
            var text = line.kind == .del ? AttributedString(line.text) : highlight(line.text)
            if line.kind == .del {
                text.foregroundColor = Color(hex: 0xff8a80, opacity: 0.7)
                text.strikethroughStyle = .single
                text.strikethroughColor = NSColor(red: 1, green: 0.54, blue: 0.5, alpha: 0.5)
            }
            var row = Row(id: rows.count, kind: line.kind, number: hunk.start > 0 ? String(number) : "", text: text, length: line.text.count)
            if line.kind == .add {
                row.delay = delay
                row.duration = min(Double(row.length) * 0.028, 0.9)
                delay += row.duration
            }
            rows.append(row)
        }
    }
    if let last = rows.lastIndex(where: { $0.kind == .add }) { rows[last].caret = true }
    return (rows, hunks.contains { $0.start > 0 }, delay)
}

struct DiffView: View {
    var hunks: [Hunk]
    var typing: UUID?
    var height: CGFloat
    @State private var started = Date.distantPast
    @State private var typed = true

    var body: some View {
        let layout = rows(hunks)
        TimelineView(.animation(paused: typed)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(started)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(layout.rows) { row in
                    if let kind = row.kind {
                        line(row, kind, numbered: layout.numbered, elapsed: elapsed)
                    } else {
                        Text("⋯").foregroundStyle(.white.opacity(0.3)).padding(.leading, 32).frame(height: 13)
                    }
                }
            }
        }
        .font(mono)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(Capped(height: height))
        .task(id: typing) {
            guard typing != nil else { return }
            started = Date()
            typed = false
            try? await Task.sleep(for: .seconds(layout.total + 3.1))
            typed = true
        }
    }

    private func line(_ row: Row, _ kind: DiffLine.Kind, numbered: Bool, elapsed: Double) -> some View {
        let tint: Color = kind == .add ? .qGreen : kind == .del ? .qRed : .clear
        let marks: Color = kind == .add ? Color(hex: 0x7ee2a0) : kind == .del ? Color(hex: 0xff8a80) : .white.opacity(0.35)
        let since = elapsed - row.delay
        let shown = kind != .add || typing == nil ? row.length : Int(min(max(since / max(row.duration, 0.001), 0), 1) * Double(row.length))
        let caret = row.caret && typing != nil && since >= 0 && since < 3 && Int(since / 0.25) % 2 == 0
        return HStack(spacing: 0) {
            Text(row.number)
                .foregroundStyle(kind == .same ? .white.opacity(0.25) : marks)
                .monospacedDigit()
                .frame(width: numbered ? 26 : 4, alignment: .trailing)
                .padding(.trailing, 6)
            Text(kind == .add ? "+" : kind == .del ? "-" : " ").foregroundStyle(marks).frame(width: 14, alignment: .leading)
            Text(shown >= row.length ? row.text : prefix(row.text, shown)).lineLimit(1).truncationMode(.tail)
            if caret { Rectangle().fill(.white).frame(width: 1.5, height: 13) }
            Spacer(minLength: 12)
        }
        .frame(height: 17.6)
        .background(kind == .same ? .clear : tint.opacity(0.14))
        .overlay(alignment: .leading) { Rectangle().fill(kind == .same ? .clear : tint).frame(width: 2) }
    }

    private func prefix(_ text: AttributedString, _ count: Int) -> AttributedString {
        AttributedString(text[text.startIndex..<text.characters.index(text.startIndex, offsetBy: count)])
    }
}
