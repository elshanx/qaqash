import type { HookEvent } from './types'

export type DiffLine = { kind: 'add' | 'del' | 'same', text: string }
export type Hunk = { start: number, lines: DiffLine[] }

const maxLines = 400
const context = 2

const linesOf = (text: string): string[] => (text === '' ? [] : text.split('\n').slice(0, maxLines))

export const diffLines = (before: string, after: string): DiffLine[] => {
  const a = linesOf(before)
  const b = linesOf(after)
  const common = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0))
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      common[i][j] = a[i] === b[j] ? common[i + 1][j + 1] + 1 : Math.max(common[i + 1][j], common[i][j + 1])
    }
  }
  const lines: DiffLine[] = []
  let i = 0
  let j = 0
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      lines.push({ kind: 'same', text: a[i] })
      i++
      j++
    } else if (i < a.length && (j === b.length || common[i + 1][j] >= common[i][j + 1])) {
      lines.push({ kind: 'del', text: a[i++] })
    } else {
      lines.push({ kind: 'add', text: b[j++] })
    }
  }
  return lines
}

const trim = (lines: DiffLine[], start: number): Hunk => {
  const changed = lines.map(({ kind }) => kind !== 'same')
  const first = changed.indexOf(true)
  if (first < 0) return { start, lines: lines.slice(0, context * 2 + 1) }
  const from = Math.max(0, first - context)
  return { start: start && start + from, lines: lines.slice(from, changed.lastIndexOf(true) + context + 1) }
}

const lineStartBefore = (text: string, index: number): number => {
  let at = index
  for (let n = 0; n <= context && at > 0; n++) at = text.lastIndexOf('\n', at - 1)
  return at <= 0 ? 0 : at + 1
}

const lineEndAfter = (text: string, index: number): number => {
  let at = index
  for (let n = 0; n <= context; n++) {
    const next = text.indexOf('\n', n === 0 ? at : at + 1)
    if (next < 0) return text.length
    at = next
  }
  return at
}

const editHunk = (text: string | null, before: string, after: string): Hunk => {
  const pending = text?.indexOf(before) ?? -1
  const applied = pending < 0 ? text?.indexOf(after) ?? -1 : -1
  if (!text || (pending < 0 && applied < 0)) return trim(diffLines(before, after), 0)
  const index = pending >= 0 ? pending : applied
  const found = pending >= 0 ? before : after
  const from = lineStartBefore(text, index)
  const window = text.slice(from, lineEndAfter(text, index + found.length))
  const offset = index - from
  const swapped = window.slice(0, offset) + (pending >= 0 ? after : before) + window.slice(offset + found.length)
  const start = text.slice(0, from).split('\n').length
  return pending >= 0 ? trim(diffLines(window, swapped), start) : trim(diffLines(swapped, window), start)
}

type Edit = { old_string?: string, new_string?: string }

const multiEditHunks = (text: string | null, edits: Edit[]): Hunk[] => {
  let current = text
  return edits.map(({ old_string: before = '', new_string: after = '' }) => {
    const hunk = editHunk(current, before, after)
    if (current?.includes(before)) current = current.replace(before, () => after)
    return hunk
  })
}

export const hunksOf = ({ tool_name: toolName, tool_input: input = {} }: HookEvent, text: string | null): Hunk[] => {
  switch (toolName) {
    case 'Edit': return [editHunk(text, String(input.old_string ?? ''), String(input.new_string ?? ''))]
    case 'MultiEdit': return multiEditHunks(text, (input.edits as Edit[] | undefined) ?? [])
    case 'Write': return [trim(diffLines(text ?? '', String(input.content ?? '')), 1)]
    default: return []
  }
}

export const changesFiles = (event: HookEvent): boolean => ['Edit', 'MultiEdit', 'Write'].includes(event.tool_name ?? '')

export const fileOf = (event: HookEvent): string => String(event.tool_input?.file_path ?? '').split('/').pop() ?? ''

const token = /(\/\/.*)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`[^`]*`)|\b(import|from|export|default|function|const|let|var|return|if|else|for|while|of|in|new|class|extends|type|interface|async|await|true|false|null|undefined|pub|fn|use|mut|impl|struct|enum|match|self)\b|\b(\d[\d_.]*)\b|\b([A-Z]\w*)\b/g
const tokenKinds = ['comment', 'string', 'keyword', 'number', 'type']

const highlight = (text: string): Node[] => {
  const nodes: Node[] = []
  let last = 0
  for (const match of text.matchAll(token)) {
    const index = match.index ?? 0
    nodes.push(document.createTextNode(text.slice(last, index)))
    const kind = tokenKinds[match.slice(1).findIndex(Boolean)]
    nodes.push(Object.assign(document.createElement('span'), { className: kind, textContent: match[0] }))
    last = index + match[0].length
  }
  nodes.push(document.createTextNode(text.slice(last)))
  return nodes
}

const marks = { add: '+', del: '-', same: ' ' }

const hunkRows = ({ start, lines }: Hunk): HTMLElement[] => {
  let oldLine = start
  let newLine = start
  return lines.map(({ kind, text }) => {
    const number = kind === 'add' ? newLine++ : oldLine++
    if (kind === 'same') newLine++
    const row = Object.assign(document.createElement('span'), { className: `line ${kind}` })
    const code = document.createElement('code')
    code.append(...(kind === 'del' ? [document.createTextNode(text)] : highlight(text)))
    row.append(
      Object.assign(document.createElement('span'), { className: 'no', textContent: start > 0 ? String(number) : '' }),
      Object.assign(document.createElement('span'), { className: 'mark', textContent: marks[kind] }),
      code,
    )
    return row
  })
}

export const renderDiff = (target: HTMLElement, hunks: Hunk[]) => {
  target.toggleAttribute('data-numbered', hunks.some(({ start }) => start > 0))
  target.replaceChildren(...hunks.flatMap((hunk, index) => [
    ...(index > 0 ? [Object.assign(document.createElement('span'), { className: 'gap', textContent: '⋯' })] : []),
    ...hunkRows(hunk),
  ]))
}
