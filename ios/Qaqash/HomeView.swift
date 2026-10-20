import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var island: Island

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Eyes(mood: island.mood, size: 18)
                        VStack(alignment: .leading) {
                            Text(island.pairing?.name ?? "Mac").font(.headline)
                            Text(island.connected ? "Connected" : "Looking for your Mac…")
                                .font(.subheadline)
                                .foregroundStyle(island.connected ? .green : .secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                ForEach(island.asks) { ask in
                    Section { AskCard(ask: ask) }
                }
                Section("Sessions") {
                    if island.sessions.isEmpty {
                        Text("No Claude Code sessions").foregroundStyle(.secondary)
                    }
                    ForEach(island.sessions) { session in
                        HStack {
                            Circle().fill(dot(session.mood)).frame(width: 8, height: 8)
                            Text(session.project)
                            Spacer()
                            Text(session.status).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Qaqash")
            .toolbar {
                Menu {
                    Button("Unpair", role: .destructive) { island.unpair() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .animation(.spring(duration: 0.4), value: island.asks)
        }
    }

    private func dot(_ mood: Mood) -> Color {
        switch mood {
        case .needs: .orange
        case .done: .green
        default: .blue
        }
    }
}

struct Question: Identifiable {
    var id: String { question }
    var question: String
    var options: [String]
    var multiple: Bool
}

struct AskCard: View {
    @EnvironmentObject private var island: Island
    let ask: Ask
    @State private var picks: [String: Set<String>] = [:]

    private var questions: [Question] {
        let input = ask.event["tool_input"] as? [String: Any] ?? [:]
        return (input["questions"] as? [[String: Any]] ?? []).map { question in
            Question(
                question: question["question"] as? String ?? "",
                options: (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String },
                multiple: question["multiSelect"] as? Bool ?? false
            )
        }
    }

    private var detail: String {
        let input = ask.event["tool_input"] as? [String: Any] ?? [:]
        return (input["command"] ?? input["file_path"] ?? input["url"]).map { "\($0)" } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(projectOf(ask.event)).font(.caption).foregroundStyle(.secondary)
            if ask.kind == "question" {
                ForEach(questions) { question in
                    Text(question.question).font(.headline)
                    ForEach(question.options, id: \.self) { option in
                        Button { pick(option, in: question) } label: {
                            HStack {
                                Text(option)
                                Spacer()
                                if picks[question.question]?.contains(option) == true {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picks.count < questions.count)
            } else {
                Text("Wants to use \(ask.event["tool_name"] as? String ?? "a tool")").font(.headline)
                if !detail.isEmpty {
                    Text(detail).font(.caption.monospaced()).lineLimit(4).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Deny", role: .destructive) { Task { await island.decide(ask, answer: false) } }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Allow") { Task { await island.decide(ask, answer: true) } }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pick(_ option: String, in question: Question) {
        var chosen = picks[question.question] ?? []
        if question.multiple {
            if chosen.contains(option) { chosen.remove(option) } else { chosen.insert(option) }
        } else {
            chosen = [option]
        }
        picks[question.question] = chosen.isEmpty ? nil : chosen
    }

    private func send() {
        let answers = Dictionary(uniqueKeysWithValues: questions.map { question in
            (question.question, question.options.filter { picks[question.question]?.contains($0) == true }.joined(separator: ", "))
        })
        Task { await island.decide(ask, answer: answers) }
    }
}
