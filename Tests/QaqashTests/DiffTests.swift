import Testing
@testable import Qaqash

private func kinds(_ before: String, _ after: String) -> [String] {
    diffLines(before, after).map { "\($0.kind):\($0.text)" }
}

private func event(_ tool: String, _ input: JSON) -> HookEvent {
    HookEvent(raw: ["hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": input])
}

private func edit(_ before: String, _ after: String) -> HookEvent {
    event("Edit", ["old_string": before, "new_string": after])
}

private func shown(_ hunks: [Hunk]) -> [[String]] {
    hunks.map { ["\($0.start)"] + $0.lines.map { "\($0.kind):\($0.text)" } }
}

private let file = "1\n2\n3\nconst TVA = 0.196\n5\n6\n7"

@Test func lines() {
    #expect(kinds("a\nb\nc", "a\nB\nc") == ["same:a", "del:b", "add:B", "same:c"])
    #expect(kinds("", "x\ny") == ["add:x", "add:y"])
    #expect(kinds("x", "") == ["del:x"])
}

@Test func hunks() {
    let expected = [["2", "same:2", "same:3", "del:const TVA = 0.196", "add:const TVA = 0.20", "same:5", "same:6"]]
    #expect(shown(hunksOf(edit("0.196", "0.20"), file)) == expected)
    #expect(shown(hunksOf(edit("0.196", "0.20"), file.replacingOccurrences(of: "0.196", with: "0.20"))) == expected)
    #expect(shown(hunksOf(edit("a", "b"), nil)) == [["0", "del:a", "add:b"]])
    #expect(shown(hunksOf(event("Write", ["content": "x"]), nil)) == [["1", "add:x"]])
    #expect(hunksOf(event("Read", [:]), file).isEmpty)
    let multi = event("MultiEdit", ["edits": [["old_string": "1", "new_string": "one"], ["old_string": "7", "new_string": "seven"]]])
    #expect(hunksOf(multi, file).map(\.start) == [1, 5])
    #expect(shown(hunksOf(edit("1", "one"), file)) == [["1", "del:1", "add:one", "same:2", "same:3"]])
}

@Test func pairCode() {
    #expect(Phone.pairCode("0000ffff") == "5535")
}
