import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'

type HookEvent = {
  hook_event_name: string
  session_id?: string
  tool_name?: string
  tool_input?: Record<string, unknown>
  message?: string
}

type PermissionRequest = {
  id: number
  event: HookEvent
}

const status = document.getElementById('status')!
const ask = document.getElementById('ask')!
const tool = document.getElementById('tool')!
const detail = document.getElementById('detail')!

let queue: PermissionRequest[] = []

const describe = (event: HookEvent): string => {
  switch (event.hook_event_name) {
    case 'UserPromptSubmit': return 'Thinking…'
    case 'PreToolUse': return event.tool_name ?? 'Working…'
    case 'Notification': return event.message ?? 'Needs you'
    case 'Stop': return 'Done'
    default: return event.hook_event_name
  }
}

const summarize = (input: Record<string, unknown> = {}): string =>
  String(input.command ?? input.file_path ?? input.url ?? JSON.stringify(input, null, 2))

const render = async () => {
  const [first] = queue
  if (!first) {
    ask.hidden = true
    await invoke('resize', { width: 370, height: 38 })
    return
  }
  const more = queue.length > 1 ? ` (+${queue.length - 1})` : ''
  tool.textContent = `Allow ${first.event.tool_name ?? 'tool'}?${more}`
  detail.textContent = summarize(first.event.tool_input)
  ask.hidden = false
  await invoke('resize', { width: 460, height: 210 })
}

const decide = async (allow: boolean) => {
  const [first] = queue
  if (!first) return
  await invoke('decide', { id: first.id, allow })
  queue = queue.filter(({ id }) => id !== first.id)
  await render()
}

const dropStale = (event: HookEvent) => {
  if (event.hook_event_name !== 'UserPromptSubmit' && event.hook_event_name !== 'Stop') return
  const before = queue.length
  queue = queue.filter((request) => request.event.session_id !== event.session_id)
  if (queue.length !== before) render()
}

document.getElementById('allow')!.addEventListener('click', () => decide(true))
document.getElementById('deny')!.addEventListener('click', () => decide(false))

listen<HookEvent>('status', ({ payload }) => {
  status.textContent = describe(payload)
  dropStale(payload)
})

listen<PermissionRequest>('permission', ({ payload }) => {
  queue = [...queue, payload]
  render()
})
