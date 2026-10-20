import AppKit
import Network

final class Pending {
    private let lock = NSLock()
    private var nextId = 0
    private var waiting: [Int: (Any?) -> Void] = [:]

    func resolve(_ id: Int, _ answer: Any?) {
        lock.withLock { waiting.removeValue(forKey: id) }?(answer)
    }

    func wait(kind: String, event: JSON, timeout: TimeInterval) -> Any? {
        let done = DispatchSemaphore(value: 0)
        var answer: Any?
        let id = lock.withLock {
            let id = nextId
            nextId += 1
            waiting[id] = { answer = $0; done.signal() }
            return id
        }
        play("Ping")
        DispatchQueue.main.async { state.ask(Ask(id: id, kind: kind, event: HookEvent(raw: event))) }
        if kind != "pair" { phone.askOpened(["id": id, "kind": kind, "event": event]) }
        let answered = done.wait(timeout: .now() + timeout) == .success
        lock.withLock { waiting[id] = nil }
        phone.askClosed(id)
        DispatchQueue.main.async { state.closeAsk(id) }
        return answered ? answer : nil
    }
}

let pending = Pending()

func play(_ sound: String) {
    guard UserDefaults.standard.bool(forKey: "sound") else { return }
    DispatchQueue.main.async { NSSound(named: sound)?.play() }
}

enum Hooks {
    private static var server: HTTPServer?

    static func start() {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let failed = {
            print("qaqash: port 47831 is in use")
            exit(1)
        }
        server = try? HTTPServer(port: 47831, parameters: parameters, failed: failed) { Response(body: handle($0)) }
    }

    private static func handle(_ request: Request) -> Data {
        guard var event = (try? JSONSerialization.jsonObject(with: request.body)) as? JSON else { return Data() }
        if let pid = Int(request.headers["x-qaqash-pid"] ?? "") { event["qaqash_pid"] = pid }
        let quiet = UserDefaults.standard.bool(forKey: "quiet") && claudeAppIsFrontmost()
        let name = event["hook_event_name"] as? String
        if name == "PermissionRequest" && !quiet { return answerPermission(event) }
        if name == "PreToolUse" && event["tool_name"] as? String == "AskUserQuestion" && !quiet { return answerQuestion(event) }
        if name == "Stop" && !quiet { play("Glass") }
        if name != "PostToolUse" { phone.status(event) }
        DispatchQueue.main.async { state.receive(HookEvent(raw: event)) }
        return Data()
    }

    private static func answerPermission(_ event: JSON) -> Data {
        guard let answer = pending.wait(kind: "permission", event: event, timeout: 580) else { return Data() }
        let decision: JSON = answer as? Bool == true ? ["behavior": "allow"] : ["behavior": "deny", "message": "Denied from Qaqash"]
        return jsonData(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
    }

    private static func answerQuestion(_ event: JSON) -> Data {
        var input = event["tool_input"] as? JSON ?? [:]
        guard let answers = pending.wait(kind: "question", event: event, timeout: 580) else { return Data() }
        input["answers"] = answers
        return jsonData(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input]])
    }
}
