import { deepEqual } from 'node:assert/strict'
import { diffLines, diffOf } from '../src/diff.ts'

const kinds = (before: string, after: string) => diffLines(before, after).map(({ kind, text }) => `${kind}:${text}`)

deepEqual(kinds('a\nb\nc', 'a\nB\nc'), ['same:a', 'del:b', 'add:B', 'same:c'])
deepEqual(kinds('', 'x\ny'), ['add:x', 'add:y'])
deepEqual(kinds('x', ''), ['del:x'])
deepEqual(kinds('same', 'same'), ['same:same'])
deepEqual(diffOf({ hook_event_name: 'PreToolUse', tool_name: 'Read' }), null)
deepEqual(diffOf({ hook_event_name: 'PreToolUse', tool_name: 'MultiEdit', tool_input: { edits: [{ old_string: 'a', new_string: 'b' }] } })?.length, 2)
console.log('diff ok')
