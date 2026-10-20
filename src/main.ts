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
const tool = document.getElementById('tool')!
const detail = document.getElementById('detail')!
const questionList = document.getElementById('questions')!
const allow = document.getElementById('allow') as HTMLButtonElement
const deny = document.getElementById('deny')!

let queue: Ask[] = []
const picks = new Map<string, string[]>()
let hovering = false
const sessions = new Map<string, { name: string, state: string }>()

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

type Mood = 'idle' | 'thinking' | 'needs' | 'done'

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

const render = async () => {
  const [first] = queue
  sessionList.hidden = true
  ask.hidden = true
  if (first) {
    const more = queue.length > 1 ? ` (+${queue.length - 1})` : ''
    const isQuestion = first.kind === 'question'
    tool.textContent = isQuestion ? `Claude asks${more}` : `Allow ${first.event.tool_name ?? 'tool'}?${more}`
    detail.hidden = isQuestion
    deny.hidden = isQuestion
    allow.textContent = isQuestion ? 'Send' : 'Allow'
    detail.textContent = isQuestion ? '' : summarize(first.event.tool_input)
    questionList.replaceChildren(...(isQuestion ? questionsOf(first).map(renderQuestion) : []))
    allow.disabled = isQuestion && questionsOf(first).some(({ question }) => !picks.get(question)?.length)
    ask.hidden = false
    const height = isQuestion ? 38 + ask.scrollHeight : 210
    await invoke('resize', { width: 460, height })
    return
  }
  if (hovering && sessions.size > 0) {
    sessionList.replaceChildren(...[...sessions.values()].map(({ name, state }) => {
      const row = document.createElement('li')
      row.append(Object.assign(document.createElement('span'), { textContent: name }))
      row.append(Object.assign(document.createElement('span'), { textContent: state }))
      return row
    }))
    sessionList.hidden = false
    await invoke('resize', { width: 460, height: 38 + sessions.size * 21 + 12 })
    return
  }
  await invoke('resize', { width: 370, height: 38 })
}

const track = (event: HookEvent) => {
  if (!event.session_id) return
  if (event.hook_event_name === 'SessionEnd') {
    sessions.delete(event.session_id)
  } else {
    const name = event.cwd?.split('/').pop() || event.session_id.slice(0, 8)
    sessions.set(event.session_id, { name, state: describe(event) })
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

pill.addEventListener('mouseenter', () => {
  hovering = true
  render()
})

pill.addEventListener('mouseleave', () => {
  hovering = false
  render()
})

listen<HookEvent>('status', ({ payload }) => {
  status.textContent = describe(payload)
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
