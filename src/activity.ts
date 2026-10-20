import { invoke } from '@tauri-apps/api/core'
import { activity, code, diffView, file, filePath, lang, steps, whoName } from './dom'
import { changesFiles, fileOf, hunksOf, renderDiff } from './diff'
import { projectOf } from './hook-events'
import { render } from './island'
import { state } from './state'
import type { HookEvent } from './types'

const lingerMs = 6000
const maxSteps = 4
let hideTimer = 0

const close = () => {
  if (state.hovering) {
    hideTimer = window.setTimeout(close, lingerMs)
    return
  }
  state.activity = null
  render()
}

type Edit = { old_string?: string, new_string?: string }

const needlesOf = (input: Record<string, unknown> = {}): string[] => {
  const edits = (input.edits as Edit[] | undefined) ?? [input as Edit]
  return edits.flatMap((edit) => [edit.new_string ?? '', edit.old_string ?? ''])
}

const openFile = () => {
  const input = state.activity?.event.tool_input
  if (typeof input?.file_path === 'string') invoke('open_in_vscode', { path: input.file_path, needles: needlesOf(input) })
}

export const startActivity = () => {
  code.addEventListener('click', openFile)
}

export const readHunks = async (event: HookEvent) => {
  const path = event.tool_input?.file_path
  const text = typeof path === 'string' ? await invoke<string | null>('read_file', { path }).catch(() => null) : null
  return hunksOf(event, text)
}

const show = () => {
  clearTimeout(hideTimer)
  hideTimer = window.setTimeout(close, lingerMs)
  render()
}

export const trackActivity = async (event: HookEvent) => {
  const { hook_event_name: name, tool_name: toolName } = event
  const current = state.activity?.event.session_id === event.session_id ? state.activity : null
  if (name === 'PreToolUse' && toolName && toolName !== 'AskUserQuestion') {
    const done = current?.steps ?? []
    state.activity = {
      event: current?.event ?? event,
      hunks: current?.hunks ?? [],
      steps: done.at(-1) === toolName ? done : [...done, toolName].slice(-maxSteps),
      done: false,
    }
    if (changesFiles(event)) {
      const hunks = await readHunks(event)
      if (state.activity?.event.session_id !== event.session_id) return
      state.activity = { ...state.activity, event, hunks }
    }
  } else if (name === 'Stop' && current) {
    state.activity = { ...current, done: true }
  } else {
    return
  }
  if (state.activity.hunks.length > 0) show()
}

const toolIcons: Record<string, string> = {
  Read: 'read',
  Edit: 'edit',
  MultiEdit: 'edit',
  Write: 'edit',
  NotebookEdit: 'edit',
  Bash: 'bash',
  Grep: 'search',
  Glob: 'search',
  WebFetch: 'web',
  WebSearch: 'web',
  Done: 'check',
}

const stepRow = (name: string, stepState: 'done' | 'running') => {
  const row = Object.assign(document.createElement('li'), { textContent: name, className: stepState })
  row.dataset.icon = toolIcons[name] ?? 'tool'
  return row
}

let shownHunks: unknown = null

const typeAddedLines = () => {
  const msPerChar = 28
  let delay = 0
  const added = [...diffView.querySelectorAll<HTMLElement>('.add code')]
  added.forEach((code, index) => {
    const chars = code.textContent?.length ?? 0
    const duration = Math.min(chars * msPerChar, 900)
    code.style.setProperty('--chars', String(chars))
    code.style.setProperty('--type-ms', `${duration}ms`)
    code.style.setProperty('--type-delay', `${delay}ms`)
    code.classList.add('typing')
    code.toggleAttribute('data-caret', index === added.length - 1)
    delay += duration
  })
}

const relativePath = ({ cwd = '', tool_input: input }: HookEvent): string => {
  const path = String(input?.file_path ?? '')
  return cwd && path.startsWith(`${cwd}/`) ? path.slice(cwd.length + 1) : path
}

export const renderActivity = () => {
  const current = state.activity
  if (!current?.hunks.length) return
  const last = current.steps.length - 1
  steps.replaceChildren(
    ...current.steps.map((name, index) => stepRow(name, index < last || current.done ? 'done' : 'running')),
    ...(current.done ? [stepRow('Done', 'done')] : []),
  )
  whoName.textContent = projectOf(current.event)
  const name = fileOf(current.event)
  file.textContent = name
  lang.textContent = name.includes('.') ? name.split('.').pop()!.slice(0, 2).toUpperCase() : ''
  lang.hidden = !lang.textContent
  filePath.textContent = `\u200E${relativePath(current.event)}\u200E`
  file.toggleAttribute('data-unsaved', !current.done && changesFiles({ hook_event_name: '', tool_name: current.steps[last] }))
  if (current.hunks !== shownHunks) {
    shownHunks = current.hunks
    renderDiff(diffView, current.hunks)
    typeAddedLines()
  }
  activity.toggleAttribute('data-entering', activity.hidden)
}
