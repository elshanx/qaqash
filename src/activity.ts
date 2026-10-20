import { invoke } from '@tauri-apps/api/core'
import { activity, diffView, file, steps } from './dom'
import { diffOf, fileOf, renderDiff } from './diff'
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
  file.addEventListener('click', openFile)
  diffView.addEventListener('click', openFile)
}

export const trackActivity = (event: HookEvent) => {
  const { hook_event_name: name, tool_name: toolName } = event
  const current = state.activity?.event.session_id === event.session_id ? state.activity : null
  if (name === 'PreToolUse' && toolName && toolName !== 'AskUserQuestion') {
    const diff = diffOf(event)
    const done = current?.steps ?? []
    state.activity = {
      event: diff ? event : current?.event ?? event,
      diff: diff ?? current?.diff ?? null,
      steps: done.at(-1) === toolName ? done : [...done, toolName].slice(-maxSteps),
      done: false,
    }
  } else if (name === 'Stop' && current) {
    state.activity = { ...current, done: true }
  } else {
    return
  }
  if (!state.activity.diff) return
  clearTimeout(hideTimer)
  hideTimer = window.setTimeout(close, lingerMs)
  render()
}

const stepRow = (name: string, stepState: 'done' | 'running') =>
  Object.assign(document.createElement('li'), { textContent: name, className: stepState })

export const renderActivity = () => {
  const current = state.activity
  if (!current?.diff) return
  const last = current.steps.length - 1
  steps.replaceChildren(
    ...current.steps.map((name, index) => stepRow(name, index < last || current.done ? 'done' : 'running')),
    ...(current.done ? [stepRow('Done', 'done')] : []),
  )
  file.textContent = fileOf(current.event)
  renderDiff(diffView, current.diff)
  activity.toggleAttribute('data-entering', activity.hidden)
}
