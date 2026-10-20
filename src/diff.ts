import type { HookEvent } from './types'

export type DiffLine = { kind: 'add' | 'del' | 'same', text: string }

const maxLines = 400

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

type Edit = { old_string?: string, new_string?: string }

export const diffOf = ({ tool_name: toolName, tool_input: input = {} }: HookEvent): DiffLine[] | null => {
  switch (toolName) {
    case 'Edit': return diffLines(String(input.old_string ?? ''), String(input.new_string ?? ''))
    case 'MultiEdit': return ((input.edits as Edit[] | undefined) ?? []).flatMap((edit) => diffLines(edit.old_string ?? '', edit.new_string ?? ''))
    case 'Write': return diffLines('', String(input.content ?? ''))
    default: return null
  }
}

export const fileOf = (event: HookEvent): string => String(event.tool_input?.file_path ?? '').split('/').pop() ?? ''

const marks = { add: '+', del: '-', same: ' ' }

export const renderDiff = (target: HTMLElement, lines: DiffLine[]) => {
  target.replaceChildren(...lines.map(({ kind, text }) =>
    Object.assign(document.createElement('span'), { className: `line ${kind}`, textContent: `${marks[kind]} ${text}` })))
}
