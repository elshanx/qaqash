import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'

type HookEvent = {
  hook_event_name: string
  session_id?: string
  cwd?: string
  transcript_path?: string
  tool_name?: string
  tool_input?: Record<string, unknown>
  message?: string
}

type Question = {
  question: string
  options: { label: string }[]
  multiSelect?: boolean
}

type Track = {
  app: 'Spotify' | 'Music'
  playing: boolean
  title: string
  artist: string
  album: string
  position: number
  duration: number
  artworkUrl?: string
}

type Ask = {
  id: number
  kind: 'permission' | 'question'
  event: HookEvent
}

const pill = document.getElementById('pill')!
const status = document.getElementById('status')!
const ask = document.getElementById('ask')!
const sessionList = document.getElementById('sessions')!
const content = document.getElementById('content')!
const tool = document.getElementById('tool')!
const detail = document.getElementById('detail')!
const questionList = document.getElementById('questions')!
const allow = document.getElementById('allow')!
const deny = document.getElementById('deny')!
const icon = document.getElementById('icon')!
const kicker = document.getElementById('kicker')!
const actions = document.getElementById('actions')!
const footer = document.getElementById('footer')!
const back = document.getElementById('back')!
const next = document.getElementById('next') as HTMLButtonElement
const player = document.getElementById('player')!
const toggle = document.getElementById('toggle')!
const progress = document.getElementById('progress')!
const elapsed = document.getElementById('elapsed')!
const remaining = document.getElementById('remaining')!

type Mood = 'idle' | 'thinking' | 'needs' | 'done'

let queue: Ask[] = []
const picks = new Map<string, string[]>()
let step = 0
let hovering = false
let lastStatus = 'peep'
let track: Track | null = null
let trackSyncedAt = 0
let musicAppArtwork: string | null = null
const sessions = new Map<string, { name: string, state: string, mood: Mood, seen: number }>()
const staleAfter = 30 * 60 * 1000
const spring = (response: number, dampingRatio: number) => {
  const stiffness = (2 * Math.PI / response) ** 2
  const damping = 4 * Math.PI * dampingRatio / response
  const step = 1 / 60
  const points = [0]
  let position = 0
  let velocity = 0
  while (points.length < 180) {
    velocity += (stiffness * (1 - position) - damping * velocity) * step
    position += velocity * step
    points.push(position)
    if (Math.abs(1 - position) < 0.001 && Math.abs(velocity) < 0.01) break
  }
  points.push(1)
  return { easing: `linear(${points.map((point) => point.toFixed(3)).join(', ')})`, ms: Math.round(points.length * step * 1000) }
}

const morph = spring(0.45, 0.68)
const pop = spring(0.32, 0.6)
document.documentElement.style.setProperty('--spring', morph.easing)
document.documentElement.style.setProperty('--spring-ms', `${morph.ms}ms`)
document.documentElement.style.setProperty('--pop', pop.easing)
document.documentElement.style.setProperty('--pop-ms', `${pop.ms}ms`)

const ear = 12
const shadowRoom = 28
const collapsedWidth = 330
const openWidth = 460
document.documentElement.style.setProperty('--open-w', `${openWidth}px`)
let barHeight = 33
let windowSize = { width: 0, height: 0 }
let shrinkTimer = 0
let renderId = 0
let bumpTimer = 0

const describe = (event: HookEvent): string => {
  switch (event.hook_event_name) {
    case 'SessionStart': return 'Ready'
    case 'SessionEnd': return 'Ended'
    case 'UserPromptSubmit': return 'Thinking…'
    case 'PreToolUse': return event.tool_name ?? 'Working…'
    case 'Notification': return event.message ?? 'Needs you'
    case 'PermissionRequest': return 'Needs you'
    case 'Stop': return 'Done'
    default: return event.hook_event_name
  }
}

const moods: Record<string, Mood> = {
  UserPromptSubmit: 'thinking',
  PreToolUse: 'thinking',
  Notification: 'needs',
  Stop: 'done',
}

const setMood = (mood: Mood) => {
  pill.dataset.mood = queue.length > 0 ? 'needs' : mood
  showCompactMusic()
}

const claudeIsBusy = () => pill.dataset.mood === 'thinking' || pill.dataset.mood === 'needs'

const showCompactMusic = () => {
  pill.toggleAttribute('data-music', Boolean(track?.playing) && !claudeIsBusy())
}

const hueOf = (text: string) => [...text].reduce((hash, char) => (hash * 31 + char.charCodeAt(0)) % 360, 7)

const spotifyCover = (url = ''): string | null => {
  try {
    const parsed = new URL(url)
    return parsed.protocol === 'https:' && parsed.hostname === 'i.scdn.co' ? parsed.href : null
  } catch {
    return null
  }
}

const paintArtwork = () => {
  const cover = musicAppArtwork ?? spotifyCover(track?.artworkUrl)
  document.querySelectorAll<HTMLElement>('.art').forEach((element) => {
    element.style.setProperty('--hue', String(hueOf(track?.album ?? '')))
    if (cover) element.style.setProperty('--art', `url("${cover}")`)
    else element.style.removeProperty('--art')
  })
  pill.style.setProperty('--tint', `hsl(${hueOf(track?.album ?? '')} 75% 65%)`)
}

const clock = (totalSeconds: number) => {
  const whole = Math.max(0, Math.floor(totalSeconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}

const updateProgress = () => {
  if (!track) return
  const playedFor = track.playing ? (Date.now() - trackSyncedAt) / 1000 : 0
  const position = Math.min(track.position + playedFor, track.duration)
  elapsed.textContent = clock(position)
  remaining.textContent = `-${clock(track.duration - position)}`
  progress.style.setProperty('--progress', String(track.duration ? position / track.duration : 0))
}

const renderPlayer = () => {
  if (!track) return
  document.getElementById('title')!.textContent = track.title
  document.getElementById('artist')!.textContent = track.artist
  progress.parentElement!.hidden = track.duration === 0
  toggle.toggleAttribute('data-playing', track.playing)
  player.toggleAttribute('data-playing', track.playing)
  updateProgress()
}

const summarize = (input: Record<string, unknown> = {}): string =>
  String(input.command ?? input.file_path ?? input.url ?? JSON.stringify(input, null, 2))

const questionsOf = (request: Ask): Question[] =>
  (request.event.tool_input?.questions as Question[] | undefined) ?? []

const pick = (question: Question, label: string) => {
  const current = picks.get(question.question) ?? []
  const chosen = !question.multiSelect
    ? [label]
    : current.includes(label) ? current.filter((picked) => picked !== label) : [...current, label]
  picks.set(question.question, chosen)
  render()
  if (!question.multiSelect) {
    const from = step
    window.setTimeout(() => {
      if (step === from) advance()
    }, 180)
  }
}

const advance = () => {
  const [first] = queue
  if (first && step < questionsOf(first).length - 1) goTo(step + 1)
  else decide(true)
}

const goTo = (target: number) => {
  step = target
  render()
  questionList.animate(
    [{ opacity: 0, transform: 'translateX(12px)', filter: 'blur(6px)' }, { opacity: 1, transform: 'none', filter: 'none' }],
    { duration: 320, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
  )
}

const recommended = / ?\(recommended\)/i

const renderOption = (question: Question, label: string): HTMLElement => {
  const button = Object.assign(document.createElement('button'), { className: 'option' })
  button.append(Object.assign(document.createElement('span'), { textContent: label.replace(recommended, '') }))
  if (recommended.test(label)) {
    button.append(Object.assign(document.createElement('span'), { className: 'badge', textContent: 'Recommended' }))
  }
  if (question.multiSelect) button.append(Object.assign(document.createElement('span'), { className: 'check' }))
  button.classList.toggle('picked', picks.get(question.question)?.includes(label) ?? false)
  button.addEventListener('click', () => pick(question, label))
  return button
}

const iconFor = (toolName = ''): string =>
  toolName === 'Bash' ? '>_' : toolName.slice(0, 1).toUpperCase() || '?'

const renderPermission = (request: Ask, more: string) => {
  icon.dataset.kind = 'permission'
  icon.textContent = iconFor(request.event.tool_name)
  kicker.textContent = `${projectOf(request.event)} wants to use${more}`
  tool.textContent = request.event.tool_name ?? 'a tool'
  detail.textContent = summarize(request.event.tool_input)
  detail.hidden = false
  actions.hidden = false
  questionList.hidden = true
  footer.hidden = true
}

const renderQuestionStep = (request: Ask, more: string) => {
  const questions = questionsOf(request)
  const current = questions[step]
  const counter = questions.length > 1 ? ` · ${step + 1} of ${questions.length}` : ''
  icon.dataset.kind = 'question'
  icon.textContent = '?'
  kicker.textContent = `${projectOf(request.event)} asks${counter}${more}`
  tool.textContent = current?.question ?? ''
  questionList.replaceChildren(...(current?.options ?? []).map(({ label }) => renderOption(current, label)))
  detail.hidden = true
  actions.hidden = true
  questionList.hidden = false
  next.hidden = !current?.multiSelect
  next.textContent = step < questions.length - 1 ? 'Next' : 'Send'
  next.disabled = !picks.get(current?.question ?? '')?.length
  back.hidden = step === 0
  footer.hidden = next.hidden && back.hidden
}

const resizeWindow = async (width: number, height: number) => {
  windowSize = { width, height }
  await invoke('resize', { width: width + ear * 2, height: height > barHeight ? height + shadowRoom : height })
}

const size = async (width: number, height: number) => {
  clearTimeout(shrinkTimer)
  if (width > windowSize.width || height > windowSize.height) {
    await resizeWindow(Math.max(width, windowSize.width), Math.max(height, windowSize.height))
  }
  pill.style.setProperty('--w', `${width}px`)
  pill.style.setProperty('--h', `${height}px`)
  pill.toggleAttribute('data-open', height > barHeight)
  shrinkTimer = window.setTimeout(() => resizeWindow(width, height), morph.ms)
}

const projectOf = (event: HookEvent): string =>
  event.cwd?.split('/').pop() || event.session_id?.slice(0, 8) || 'Claude'

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

const bump = () => {
  if (pill.hasAttribute('data-open')) return
  clearTimeout(bumpTimer)
  size(collapsedWidth + 18, barHeight)
  bumpTimer = window.setTimeout(() => {
    if (!pill.hasAttribute('data-open')) size(collapsedWidth, barHeight)
  }, 140)
}

const showStatus = (text: string) => {
  if (status.textContent === text) return
  status.textContent = text
  bump()
  status.animate(
    [{ opacity: 0, transform: 'translateY(4px)', filter: 'blur(3px)' }, { opacity: 0.8, transform: 'none', filter: 'none' }],
    { duration: 280, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
  )
}

const sessionRow = ({ name, state, mood }: { name: string, state: string, mood: Mood }, index: number) => {
  const row = document.createElement('li')
  row.dataset.mood = mood
  row.style.setProperty('--i', String(index))
  row.append(Object.assign(document.createElement('span'), { textContent: name }))
  row.append(Object.assign(document.createElement('span'), { textContent: state }))
  return row
}

const render = async () => {
  const id = ++renderId
  const [first] = queue
  const showSessions = !first && hovering && sessions.size > 0
  const showPlayer = !first && hovering && Boolean(track)
  const open = Boolean(first) || showSessions || showPlayer
  if (!open && pill.hasAttribute('data-open')) {
    content.setAttribute('data-leaving', '')
    await sleep(140)
    if (id !== renderId) return
  }
  content.removeAttribute('data-leaving')
  clearTimeout(bumpTimer)
  showStatus(first ? projectOf(first.event) : lastStatus)
  if (first) {
    const more = queue.length > 1 ? ` · +${queue.length - 1} more` : ''
    if (first.kind === 'question') renderQuestionStep(first, more)
    else renderPermission(first, more)
  }
  if (showPlayer) {
    player.toggleAttribute('data-entering', player.hidden)
    renderPlayer()
  }
  if (showSessions) {
    sessionList.toggleAttribute('data-entering', sessionList.hidden)
    sessionList.replaceChildren(...[...sessions.values()].map(sessionRow))
  }
  ask.hidden = !first
  detail.toggleAttribute('data-overflowing', !detail.hidden && detail.scrollHeight > 72)
  sessionList.hidden = !showSessions
  player.hidden = !showPlayer
  await size(open ? openWidth : collapsedWidth, open ? barHeight + content.offsetHeight : barHeight)
}

const trackSession = (event: HookEvent) => {
  if (!event.session_id || !event.transcript_path) return
  if (event.hook_event_name === 'SessionEnd') {
    sessions.delete(event.session_id)
  } else {
    const name = projectOf(event)
    sessions.set(event.session_id, { name, state: describe(event), mood: moods[event.hook_event_name] ?? 'thinking', seen: Date.now() })
  }
  if (hovering) render()
}

const remove = (id: number) => {
  if (queue[0]?.id === id) {
    picks.clear()
    step = 0
  }
  queue = queue.filter((request) => request.id !== id)
}

const decide = async (allowed: boolean) => {
  const [first] = queue
  if (!first) return
  const answer = first.kind === 'question'
    ? Object.fromEntries(questionsOf(first).map(({ question }) => [question, picks.get(question)?.join(', ') ?? '']))
    : allowed
  await invoke('decide', { id: first.id, answer })
  remove(first.id)
  setMood('thinking')
  await render()
}

const dropStale = (event: HookEvent) => {
  if (event.hook_event_name !== 'UserPromptSubmit' && event.hook_event_name !== 'Stop') return
  const before = queue.length
  queue = queue.filter((request) => request.event.session_id !== event.session_id)
  if (queue.length !== before) render()
}

allow.addEventListener('click', () => decide(true))
deny.addEventListener('click', () => decide(false))
next.addEventListener('click', advance)
back.addEventListener('click', () => goTo(step - 1))

setInterval(() => {
  const cutoff = Date.now() - staleAfter
  sessions.forEach(({ seen }, id) => {
    if (seen < cutoff) sessions.delete(id)
  })
  if (hovering) render()
}, 60 * 1000)

pill.addEventListener('mouseenter', () => {
  hovering = true
  render()
})

pill.addEventListener('mouseleave', () => {
  hovering = false
  render()
})

listen<HookEvent>('status', ({ payload }) => {
  lastStatus = describe(payload)
  if (queue.length === 0) showStatus(lastStatus)
  dropStale(payload)
  trackSession(payload)
  setMood(moods[payload.hook_event_name] ?? 'thinking')
})

listen<Ask>('ask', ({ payload }) => {
  queue = [...queue, payload]
  setMood('needs')
  render()
})

const albumKey = (playing: Track | null) => (playing ? `${playing.app}:${playing.album}` : '')

const loadArtwork = async () => {
  const bytes = track?.app === 'Music' ? await invoke<number[] | null>('music_artwork') : null
  if (musicAppArtwork) URL.revokeObjectURL(musicAppArtwork)
  musicAppArtwork = bytes ? URL.createObjectURL(new Blob([new Uint8Array(bytes)])) : null
  paintArtwork()
}

listen<Track | null>('music', ({ payload }) => {
  const wasShown = Boolean(track)
  const albumChanged = albumKey(track) !== albumKey(payload)
  track = payload
  trackSyncedAt = Date.now()
  if (albumChanged) loadArtwork()
  showCompactMusic()
  if (hovering && wasShown !== Boolean(track)) render()
  else if (!player.hidden) renderPlayer()
})

document.querySelectorAll<HTMLButtonElement>('#controls button').forEach((button) => {
  button.addEventListener('click', async () => {
    if (!track) return
    const action = button.dataset.action
    await invoke('music_control', { player: track.app, action })
    if (action === 'toggle') {
      track = { ...track, playing: !track.playing, position: track.position + (track.playing ? (Date.now() - trackSyncedAt) / 1000 : 0) }
      trackSyncedAt = Date.now()
      showCompactMusic()
      renderPlayer()
    }
  })
})

setInterval(() => {
  if (!player.hidden) updateProgress()
}, 500)

listen<number>('expired', ({ payload }) => {
  remove(payload)
  setMood('thinking')
  render()
})

invoke<number>('menu_bar_height').catch(() => 0).then((height) => {
  barHeight = height || barHeight
  document.documentElement.style.setProperty('--bar', `${barHeight}px`)
  render()
})
