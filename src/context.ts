import { invoke } from '@tauri-apps/api/core'
import { island } from './dom'
import { sessions } from './state'
import type { HookEvent } from './types'

const smallWindow = 200_000
const largeWindow = 1_000_000
const readOn = ['UserPromptSubmit', 'PreToolUse', 'Stop']

export const contextShare = (used: number) => Math.min(used / (used > smallWindow ? largeWindow : smallWindow), 1)

export const trackContext = async (event: HookEvent) => {
  if (!event.transcript_path || !readOn.includes(event.hook_event_name)) return
  const used = await invoke<number | null>('context_used', { path: event.transcript_path }).catch(() => null)
  if (used === null) return
  const session = sessions.get(event.session_id ?? '')
  if (session) session.context = used
  const share = contextShare(used)
  island.style.setProperty('--context', String(share))
  island.dataset.context = share > 0.95 ? 'full' : share > 0.8 ? 'high' : 'ok'
}
