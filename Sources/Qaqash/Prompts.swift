import SwiftUI

struct Question {
    var question: String
    var options: [String]
    var multiSelect: Bool
}

private let recommended = try! NSRegularExpression(pattern: " ?\\(recommended\\)", options: .caseInsensitive)

private func questionsOf(_ ask: Ask) -> [Question] {
    (ask.event.input["questions"] as? [JSON] ?? []).map {
        Question(question: $0["question"] as? String ?? "", options: ($0["options"] as? [JSON] ?? []).map { $0["label"] as? String ?? "" }, multiSelect: $0["multiSelect"] as? Bool ?? false)
    }
}

extension AppState {
    func ask(_ ask: Ask) {
        withAnimation(.morph) {
            queue.append(ask)
            setMood(.needs)
        }
        guard ask.kind == "permission", changesFiles(ask.event.toolName) else { return }
        DispatchQueue.global().async {
            let full = readHunks(ask.event)
            DispatchQueue.main.async {
                guard !full.isEmpty, self.queue.contains(where: { $0.id == ask.id }) else { return }
                withAnimation(.morph) { self.askHunks[ask.id] = full }
            }
        }
    }

    func closeAsk(_ id: Int) {
        guard queue.contains(where: { $0.id == id }) else { return }
        withAnimation(.morph) {
            remove(id)
            setMood(.thinking)
        }
    }

    private func remove(_ id: Int) {
        if queue.first?.id == id {
            picks = [:]
            step = 0
        }
        queue.removeAll { $0.id == id }
        askHunks[id] = nil
    }

    func decide(_ allowed: Bool) {
        guard let first = queue.first else { return }
        let answer: Any = first.kind == "question"
            ? Dictionary(questionsOf(first).map { ($0.question, picks[$0.question]?.joined(separator: ", ") ?? "") }, uniquingKeysWith: { a, _ in a })
            : allowed
        pending.resolve(first.id, answer)
        withAnimation(.morph) {
            remove(first.id)
            setMood(.thinking)
        }
    }

    func goTo(_ target: Int) {
        withAnimation(.morph) { step = target }
    }

    func advance() {
        guard let first = queue.first else { return }
        if step < questionsOf(first).count - 1 { goTo(step + 1) } else { decide(true) }
    }

    func pick(_ question: Question, _ label: String) {
        let current = picks[question.question] ?? []
        picks[question.question] = !question.multiSelect ? [label] : current.contains(label) ? current.filter { $0 != label } : current + [label]
        guard !question.multiSelect else { return }
        let from = step
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            if step == from { advance() }
        }
    }

    func dropStale(_ event: HookEvent) {
        guard event.name == "UserPromptSubmit" || event.name == "Stop" else { return }
        for ask in queue where ask.event.sessionId == event.sessionId {
            pending.resolve(ask.id, nil)
            remove(ask.id)
        }
    }
}

struct PromptView: View {
    var ask: Ask

    var body: some View {
        let more = state.queue.count > 1 ? " · +\(state.queue.count - 1) more" : ""
        VStack(alignment: .leading, spacing: 12) {
            switch ask.kind {
            case "pair": pairing
            case "question": question(more)
            default: permission(more)
            }
        }
        .padding(.top, 6)
    }

    private func head(icon: String, question: Bool = false, kicker: String, title: String, actions: Bool) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(question ? .system(size: 20, weight: .bold) : .system(size: 14, weight: .semibold, design: .monospaced))
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: question ? [Color(hex: 0xffb340), .qOrange] : [Color(hex: 0x3a3a3c), .field], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(kicker).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Text(title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if actions {
                HStack(spacing: 10) {
                    round("xmark", Color(hex: 0xff3b30), Color(hex: 0xff5147)) { state.decide(false) }
                    round("checkmark", Color(hex: 0x34c759), Color(hex: 0x48d06b)) { state.decide(true) }
                }
            }
        }
    }

    private func round(_ symbol: String, _ color: Color, _ hover: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).frame(width: 40, height: 40).hoverFill(color, hover, in: Circle())
        }
        .buttonStyle(Press())
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(mono)
            .lineSpacing(3)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(Capped(height: 54, fade: true))
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color.field, in: RoundedRectangle(cornerRadius: 12))
    }

    private var pairing: some View {
        Group {
            head(icon: "⇄", kicker: "Wants to pair with this Mac", title: ask.event.raw["device"] as? String ?? "iPhone", actions: true)
            detail("Code \(ask.event.raw["code"] as? String ?? ""). Allow only if your iPhone shows the same code.")
        }
    }

    @ViewBuilder private func permission(_ more: String) -> some View {
        let tool = ask.event.toolName ?? ""
        let edits = changesFiles(tool)
        let hunks = state.askHunks[ask.id] ?? hunksOf(ask.event, nil)
        head(icon: tool == "Bash" ? ">_" : tool.prefix(1).uppercased().isEmpty ? "?" : tool.prefix(1).uppercased(),
             kicker: "\(projectOf(ask.event)) wants to use\(more)",
             title: [tool.isEmpty ? "a tool" : tool, edits ? fileOf(ask.event) : ""].filter { !$0.isEmpty }.joined(separator: " · "),
             actions: true)
        if hunks.isEmpty {
            detail(summarize(ask.event.input))
        } else {
            DiffView(hunks: hunks, height: 176).background(Color.field, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private func question(_ more: String) -> some View {
        let questions = questionsOf(ask)
        let step = min(state.step, max(questions.count - 1, 0))
        let current = questions.isEmpty ? nil : questions[step]
        let counter = questions.count > 1 ? " · \(step + 1) of \(questions.count)" : ""
        head(icon: "?", question: true, kicker: "\(projectOf(ask.event)) asks\(counter)\(more)", title: current?.question ?? "", actions: false)
        if let current {
            VStack(spacing: 6) {
                ForEach(current.options, id: \.self) { option(current, $0) }
            }
            .id(step)
            .transition(.asymmetric(insertion: .modifier(active: Slide(on: true), identity: Slide(on: false)).animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)), removal: .opacity.animation(.linear(duration: 0.05))))
            let picked = !(state.picks[current.question] ?? []).isEmpty
            if current.multiSelect || step > 0 {
                HStack {
                    if step > 0 { pill("Back", .fieldHover) { state.goTo(step - 1) } }
                    Spacer()
                    if current.multiSelect {
                        pill(step < questions.count - 1 ? "Next" : "Send", .qBlue) { state.advance() }.disabled(!picked).opacity(picked ? 1 : 0.35)
                    }
                }
            }
        }
    }

    private func option(_ question: Question, _ label: String) -> some View {
        let picked = state.picks[question.question]?.contains(label) ?? false
        let range = NSRange(location: 0, length: (label as NSString).length)
        let isRecommended = recommended.firstMatch(in: label, range: range) != nil
        return Button { state.pick(question, label) } label: {
            HStack(spacing: 8) {
                Text(recommended.stringByReplacingMatches(in: label, range: range, withTemplate: "")).font(.system(size: 13))
                if isRecommended {
                    Text("Recommended").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7).padding(.vertical, 2).background(.white.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
                if question.multiSelect {
                    Circle().fill(picked ? Color.qBlue : .clear).frame(width: 16, height: 16)
                        .overlay { Circle().strokeBorder(picked ? Color(hex: 0x0f2a4a) : .white.opacity(0.35), lineWidth: picked ? 4 : 1.5) }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .hoverFill(picked ? Color.qBlue.opacity(0.22) : .field, picked ? Color.qBlue.opacity(0.22) : .fieldHover, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(picked ? Color.qBlue : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(Press())
    }

    private func pill(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(.semibold).padding(.vertical, 7).padding(.horizontal, 16).hoverFill(color, color == .qBlue ? color : Color(hex: 0x3a3a3c), in: Capsule())
        }
        .buttonStyle(Press())
    }
}

private struct Slide: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        content.opacity(on ? 0 : 1).offset(x: on ? 12 : 0).blur(radius: on ? 6 : 0)
    }
}
