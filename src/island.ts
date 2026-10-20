import { invoke } from '@tauri-apps/api/core'
import { renderActivity } from './activity'
import { activity, ask, content, detail, island, player, sessionList, status } from './dom'
import { projectOf } from './hook-events'
import { markHot } from './hover'
import { wobble } from './liquid'
import { morph, sleep } from './motion'
import { renderPlayer } from './music'
import { renderPrompt } from './prompts'
import { sessionRow } from './sessions'
import { sessions, state } from './state'

const collapsedWidth = 330
const openWidth = 460
document.documentElement.style.setProperty('--open-w', `${openWidth}px`)

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
  const showActivity = !first && Boolean(state.activity?.diff)
  const showSessions = !first && !showActivity && state.hovering && sessions.size > 0
  const showPlayer = !first && !showActivity && state.hovering && Boolean(state.track)
  const open = Boolean(first) || showSessions || showPlayer || showActivity
  if (!open && island.hasAttribute('data-open')) {
    content.setAttribute('data-leaving', '')
    size(collapsedWidth, state.barHeight)
    await sleep(morph.ms)
    if (id !== renderId) return
  }
  content.removeAttribute('data-leaving')
  clearTimeout(bumpTimer)
  showStatus(first ? (first.kind === 'pair' ? 'Pairing' : projectOf(first.event)) : state.lastStatus)
  if (first) renderPrompt(first)
  if (showPlayer) {
    player.toggleAttribute('data-entering', player.hidden)
    renderPlayer()
  }
  if (showSessions) {
    sessionList.toggleAttribute('data-entering', sessionList.hidden)
    sessionList.replaceChildren(...[...sessions.values()].map(sessionRow))
  }
  if (showActivity) renderActivity()
  ask.hidden = !first
  activity.hidden = !showActivity
  detail.toggleAttribute('data-overflowing', !detail.hidden && detail.scrollHeight > detail.clientHeight)
  sessionList.hidden = !showSessions
  player.hidden = !showPlayer
  markHot()
  size(open ? openWidth : collapsedWidth, open ? state.barHeight + content.offsetHeight : state.barHeight)
}
