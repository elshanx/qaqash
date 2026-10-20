import { invoke } from '@tauri-apps/api/core'
import { renderActivity } from './activity'
import { activity, ask, content, miniPlayer, settingsPage, tabs, detail, island, player, sessionList, status } from './dom'
import { projectOf } from './hook-events'
import { markHot } from './hover'
import { wobble } from './liquid'
import { morph, sleep } from './motion'
import { renderPlayer } from './music'
import { renderPrompt } from './prompts'
import { sessionRow } from './sessions'
import { renderSettings, settings } from './settings'
import { sessions, state } from './state'
import { renderTabs } from './tabs'
import { vscodeRow } from './vscode'

const collapsedWidth = 330
const openWidth = 460
const activityWidth = 510

let renderId = 0
let bumpTimer = 0

const size = (width: number, height: number) => {
  island.style.setProperty('--w', `${width}px`)
  island.style.setProperty('--h', `${height}px`)
  island.toggleAttribute('data-open', height > state.barHeight)
  wobble(width, height)
  invoke('set_hit_area', { width, height })
}

const bump = () => {
  if (island.hasAttribute('data-open')) return
  clearTimeout(bumpTimer)
  size(collapsedWidth + 18, state.barHeight)
  bumpTimer = window.setTimeout(() => {
    if (!island.hasAttribute('data-open')) size(collapsedWidth, state.barHeight)
  }, 140)
}

export const showStatus = (text: string) => {
  if (status.textContent === text) return
  status.textContent = text
  bump()
  status.animate(
    [{ opacity: 0, transform: 'translateY(4px)', filter: 'blur(3px)' }, { opacity: 0.8, transform: 'none', filter: 'none' }],
    { duration: 280, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
  )
}

export const render = async () => {
  const id = ++renderId
  const [first] = state.queue
  const working = settings.editPanel && Boolean(state.activity?.hunks.length)
  const page = first ? 'prompt' : state.hovering ? state.tab : working ? 'home' : null
  const home = page === 'home'
  const showActivity = home && working
  const showPlayer = home && !working
  const showMini = showActivity
  const list = page === 'sessions' ? 'all' : home && state.vscode ? 'vscode' : null
  const showSessions = Boolean(list)
  const showSettings = page === 'settings'
  const showTabs = !first && state.hovering
  const open = page !== null
  if (!open && island.hasAttribute('data-open')) {
    content.setAttribute('data-leaving', '')
    size(collapsedWidth, state.barHeight)
    await sleep(morph.ms)
    if (id !== renderId) return
  }
  content.removeAttribute('data-leaving')
  const width = showActivity ? activityWidth : openWidth
  document.documentElement.style.setProperty('--open-w', `${width}px`)
  clearTimeout(bumpTimer)
  showStatus(first ? (first.kind === 'pair' ? 'Pairing' : projectOf(first.event)) : state.lastStatus)
  if (first) renderPrompt(first)
  if (showTabs) renderTabs()
  if (showPlayer || showMini) {
    player.toggleAttribute('data-entering', player.hidden)
    renderPlayer()
  }
  if (showSessions) {
    sessionList.toggleAttribute('data-entering', sessionList.hidden)
    const offset = state.vscode ? 1 : 0
    sessionList.replaceChildren(
      ...(state.vscode ? [vscodeRow(state.vscode)] : []),
      ...(list === 'all' ? [...sessions.values()].map((session, index) => sessionRow(session, index + offset)) : []),
    )
  }
  if (showSettings) renderSettings()
  if (showActivity) renderActivity()
  tabs.hidden = !showTabs
  ask.hidden = !first
  activity.hidden = !showActivity
  detail.toggleAttribute('data-overflowing', !detail.hidden && detail.scrollHeight > detail.clientHeight)
  sessionList.hidden = !showSessions
  player.hidden = !showPlayer
  miniPlayer.hidden = !showMini
  settingsPage.hidden = !showSettings
  markHot()
  size(open ? width : collapsedWidth, open ? state.barHeight + content.offsetHeight : state.barHeight)
}
