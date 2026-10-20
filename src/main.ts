import './styles/base.css'
import './styles/island.css'
import './styles/liquid.css'
import './styles/face.css'
import './styles/prompt.css'
import './styles/sessions.css'
import './styles/music.css'
import './styles/activity.css'
import './styles/tabs.css'
import './styles/vscode.css'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { startActivity, trackActivity } from './activity'
import { trackContext } from './context'
import { describe, moodOf } from './hook-events'
import { startHover } from './hover'
import { render, showStatus } from './island'
import { setMood } from './mood'
import { startMusic } from './music'
import { dropStale, startPrompts } from './prompts'
import { startSessions, trackSession } from './sessions'
import { startSettings } from './settings'
import { startTabs } from './tabs'
import { startVSCode } from './vscode'
import { state } from './state'
import type { HookEvent } from './types'

listen<HookEvent>('status', ({ payload }) => {
  state.lastStatus = describe(payload)
  if (state.queue.length === 0) showStatus(state.lastStatus)
  dropStale(payload)
  trackSession(payload)
  trackActivity(payload)
  trackContext(payload)
  setMood(moodOf(payload))
})

startHover()
startActivity()
startTabs()
startVSCode()
startSettings()
startPrompts()
startSessions()
startMusic()

invoke<number>('menu_bar_height').catch(() => 0).then((height) => {
  state.barHeight = height || state.barHeight
  document.documentElement.style.setProperty('--bar', `${state.barHeight}px`)
  render()
})
