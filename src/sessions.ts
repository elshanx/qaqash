import { invoke } from '@tauri-apps/api/core'
import { changesFiles, fileOf } from './diff'
import { describe, moodOf, projectOf } from './hook-events'
import { render } from './island'
import { sessions, state } from './state'
import type { HookEvent, Session } from './types'
import { vscodeId } from './vscode'

const staleAfter = 30 * 60 * 1000

export const sessionRow = ({ name, state: activity, mood, pid, app, lastFile }: Session, index: number) => {
  const row = document.createElement('li')
  row.dataset.mood = mood
  if (pid) {
    row.toggleAttribute('data-open-source', true)
    row.addEventListener('click', () => invoke('open_session', { pid }))
  }
  row.style.setProperty('--i', String(index))
  row.append(Object.assign(document.createElement('span'), { textContent: name }))
  row.append(Object.assign(document.createElement('span'), { textContent: [activity, lastFile, app === vscodeId && 'VS Code'].filter(Boolean).join(' · ') }))
  return row
}

export const trackSession = (event: HookEvent) => {
  if (!event.session_id || !event.transcript_path) return
  if (event.hook_event_name === 'SessionEnd') {
    sessions.delete(event.session_id)
  } else {
    const id = event.session_id
    const known = sessions.get(id)
    const pid = event.qaqash_pid ?? known?.pid
    sessions.set(id, {
      name: known?.name ?? projectOf(event),
      state: describe(event),
      mood: moodOf(event),
      seen: Date.now(),
      pid,
      app: known?.app,
      lastFile: changesFiles(event) ? fileOf(event) : known?.lastFile,
    })
    if (pid && pid !== known?.pid) {
      invoke<string | null>('session_app', { pid }).then((app) => {
        const session = sessions.get(id)
        if (session && app) session.app = app
      })
    }
  }
  if (state.hovering) render()
}

export const startSessions = () => {
  setInterval(() => {
    const cutoff = Date.now() - staleAfter
    sessions.forEach(({ seen }, id) => {
      if (seen < cutoff) sessions.delete(id)
    })
    if (state.hovering) render()
  }, 60 * 1000)
}
