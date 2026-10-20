import { deepEqual } from 'node:assert/strict'
import { diffLines, hunksOf } from '../src/diff.ts'

const kinds = (before: string, after: string) => diffLines(before, after).map(({ kind, text }) => `${kind}:${text}`)
const edit = (old_string: string, new_string: string) => ({ hook_event_name: 'PreToolUse', tool_name: 'Edit', tool_input: { old_string, new_string } })
const shown = (hunks: ReturnType<typeof hunksOf>) => hunks.map((hunk) => [hunk.start, ...hunk.lines.map(({ kind, text }) => `${kind}:${text}`)])

deepEqual(kinds('a\nb\nc', 'a\nB\nc'), ['same:a', 'del:b', 'add:B', 'same:c'])
deepEqual(kinds('', 'x\ny'), ['add:x', 'add:y'])
deepEqual(kinds('x', ''), ['del:x'])

const file = '1\n2\n3\nconst TVA = 0.196\n5\n6\n7'
const expected = [2, 'same:2', 'same:3', 'del:const TVA = 0.196', 'add:const TVA = 0.20', 'same:5', 'same:6']
deepEqual(shown(hunksOf(edit('0.196', '0.20'), file)), [expected])
deepEqual(shown(hunksOf(edit('0.196', '0.20'), file.replace('0.196', '0.20'))), [expected])
deepEqual(shown(hunksOf(edit('a', 'b'), null)), [[0, 'del:a', 'add:b']])
deepEqual(shown(hunksOf({ hook_event_name: 'PreToolUse', tool_name: 'Write', tool_input: { content: 'x' } }, null)), [[1, 'add:x']])
deepEqual(hunksOf({ hook_event_name: 'PreToolUse', tool_name: 'Read' }, file), [])
const multi = { hook_event_name: 'PreToolUse', tool_name: 'MultiEdit', tool_input: { edits: [{ old_string: '1', new_string: 'one' }, { old_string: '7', new_string: 'seven' }] } }
deepEqual(shown(hunksOf(multi, file)).map(([start]) => start), [1, 5])
deepEqual(shown(hunksOf(edit('1', 'one'), file)), [[1, 'del:1', 'add:one', 'same:2', 'same:3']])
console.log('diff ok')
