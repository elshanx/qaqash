import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'

type HookEvent = {
  hook_event_name: string
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

let currentId: number | null = null

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

const showRequest = async ({ id, event }: PermissionRequest) => {
  currentId = id
  tool.textContent = `Allow ${event.tool_name ?? 'tool'}?`
  detail.textContent = summarize(event.tool_input)
  ask.hidden = false
  await invoke('resize', { width: 460, height: 210 })
}

const decide = async (allow: boolean) => {
  if (currentId === null) return
  await invoke('decide', { id: currentId, allow })
  currentId = null
  ask.hidden = true
  await invoke('resize', { width: 370, height: 38 })
}

document.getElementById('allow')!.addEventListener('click', () => decide(true))
document.getElementById('deny')!.addEventListener('click', () => decide(false))

listen<HookEvent>('status', ({ payload }) => {
  status.textContent = describe(payload)
})

listen<PermissionRequest>('permission', ({ payload }) => showRequest(payload))
