import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'

type HookEvent = {
  hook_event_name: string
  session_id?: string
  cwd?: string
  tool_name?: string
  tool_input?: Record<string, unknown>
  message?: string
}

type Question = {
  question: string
  options: { label: string }[]
  multiSelect?: boolean
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
const allow = document.getElementById('allow') as HTMLButtonElement
const deny = document.getElementById('deny')!

type Mood = 'idle' | 'thinking' | 'needs' | 'done'

let queue: Ask[] = []
const picks = new Map<string, string[]>()
let hovering = false
let lastStatus = 'peep'
const sessions = new Map<string, { name: string, state: string, mood: Mood, seen: number }>()
const staleAfter = 30 * 60 * 1000
const ear = 12
const springMs = 450
let windowSize = { width: 0, height: 0 }
let shrinkTimer = 0

const describe = (event: HookEvent): string => {
  switch (event.hook_event_name) {
    case 'SessionStart': return 'Ready'
    case 'SessionEnd': return 'Ended'
    case 'UserPromptSubmit': return 'Thinking…'
    case 'PreToolUse': return event.tool_name ?? 'Working…'
    case 'Notification': return event.message ?? 'Needs you'
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
}

const summarize = (input: Record<string, unknown> = {}): string =>
  String(input.command ?? input.file_path ?? input.url ?? JSON.stringify(input, null, 2))

const questionsOf = (request: Ask): Question[] =>
  (request.event.tool_input?.questions as Question[] | undefined) ?? []

const pick = (question: Question, label: string) => {
  const current = picks.get(question.question) ?? []
  const next = !question.multiSelect
    ? [label]
    : current.includes(label) ? current.filter((picked) => picked !== label) : [...current, label]
  picks.set(question.question, next)
  render()
}

const renderQuestion = (question: Question): HTMLElement => {
  const block = document.createElement('div')
  block.append(Object.assign(document.createElement('div'), { textContent: question.question }))
  const options = Object.assign(document.createElement('div'), { className: 'options' })
  options.append(...question.options.map(({ label }) => {
    const button = Object.assign(document.createElement('button'), { textContent: label })
    button.classList.toggle('picked', picks.get(question.question)?.includes(label) ?? false)
    button.addEventListener('click', () => pick(question, label))
    return button
  }))
  block.append(options)
  return block
}

const resizeWindow = async (width: number, height: number) => {
  windowSize = { width, height }
  await invoke('resize', { width: width + ear * 2, height })
}

const size = async (width: number, height: number) => {
  clearTimeout(shrinkTimer)
  if (width > windowSize.width || height > windowSize.height) {
    await resizeWindow(Math.max(width, windowSize.width), Math.max(height, windowSize.height))
  }
  pill.style.setProperty('--w', `${width}px`)
  pill.style.setProperty('--h', `${height}px`)
  pill.toggleAttribute('data-open', height > 38)
  shrinkTimer = window.setTimeout(() => resizeWindow(width, height), springMs)
}

const projectOf = (event: HookEvent): string =>
  event.cwd?.split('/').pop() || event.session_id?.slice(0, 8) || 'Claude'

const showStatus = (text: string) => {
  if (status.textContent === text) return
  status.textContent = text
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
  const [first] = queue
  const showSessions = !first && hovering && sessions.size > 0
  showStatus(first ? projectOf(first.event) : lastStatus)
  if (first) {
    const more = queue.length > 1 ? ` (+${queue.length - 1})` : ''
    const isQuestion = first.kind === 'question'
    tool.textContent = isQuestion ? `Claude asks${more}` : `Allow ${first.event.tool_name ?? 'tool'}?${more}`
    detail.hidden = isQuestion
    questionList.hidden = !isQuestion
    deny.hidden = isQuestion
    allow.textContent = isQuestion ? 'Send' : 'Allow'
    detail.textContent = isQuestion ? '' : summarize(first.event.tool_input)
    questionList.replaceChildren(...(isQuestion ? questionsOf(first).map(renderQuestion) : []))
    allow.disabled = isQuestion && questionsOf(first).some(({ question }) => !picks.get(question)?.length)
  }
  if (showSessions) {
    sessionList.toggleAttribute('data-entering', sessionList.hidden)
    sessionList.replaceChildren(...[...sessions.values()].map(sessionRow))
  }
  ask.hidden = !first
  sessionList.hidden = !showSessions
  const open = Boolean(first) || showSessions
  await size(open ? 460 : 330, open ? 38 + content.offsetHeight : 38)
}

const track = (event: HookEvent) => {
  if (!event.session_id) return
  if (event.hook_event_name === 'SessionEnd') {
    sessions.delete(event.session_id)
  } else {
    const name = projectOf(event)
    sessions.set(event.session_id, { name, state: describe(event), mood: moods[event.hook_event_name] ?? 'thinking', seen: Date.now() })
  }
  if (hovering) render()
}

const remove = (id: number) => {
  if (queue[0]?.id === id) picks.clear()
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
  track(payload)
  setMood(moods[payload.hook_event_name] ?? 'thinking')
})

listen<Ask>('ask', ({ payload }) => {
  queue = [...queue, payload]
  setMood('needs')
  render()
})

listen<number>('expired', ({ payload }) => {
  remove(payload)
  setMood('thinking')
  render()
})

render()
