import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { actions, allow, back, deny, detail, footer, icon, kicker, next, questionList, tool } from './dom'
import { readHunk } from './activity'
import { changesFiles, fileOf, hunkOf, renderDiff } from './diff'
import type { Hunk } from './diff'
import { projectOf, summarize } from './hook-events'
import { render } from './island'
import { setMood } from './mood'
import { picks, state } from './state'
import type { Ask, HookEvent, Question } from './types'

const recommended = / ?\(recommended\)/i
const hunks = new Map<number, Hunk>()

const questionsOf = (request: Ask): Question[] =>
  (request.event.tool_input?.questions as Question[] | undefined) ?? []

const iconFor = (toolName = ''): string =>
  toolName === 'Bash' ? '>_' : toolName.slice(0, 1).toUpperCase() || '?'

const remove = (id: number) => {
  if (state.queue[0]?.id === id) {
    picks.clear()
    state.step = 0
  }
  state.queue = state.queue.filter((request) => request.id !== id)
  hunks.delete(id)
}

const decide = async (allowed: boolean) => {
  const [first] = state.queue
  if (!first) return
  const answer = first.kind === 'question'
    ? Object.fromEntries(questionsOf(first).map(({ question }) => [question, picks.get(question)?.join(', ') ?? '']))
    : allowed
  await invoke('decide', { id: first.id, answer })
  remove(first.id)
  setMood('thinking')
  await render()
}

const goTo = (target: number) => {
  state.step = target
  render()
  questionList.animate(
    [{ opacity: 0, transform: 'translateX(12px)', filter: 'blur(6px)' }, { opacity: 1, transform: 'none', filter: 'none' }],
    { duration: 320, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
  )
}

const advance = () => {
  const [first] = state.queue
  if (first && state.step < questionsOf(first).length - 1) goTo(state.step + 1)
  else decide(true)
}

const pick = (question: Question, label: string) => {
  const current = picks.get(question.question) ?? []
  const chosen = !question.multiSelect
    ? [label]
    : current.includes(label) ? current.filter((picked) => picked !== label) : [...current, label]
  picks.set(question.question, chosen)
  render()
  if (!question.multiSelect) {
    const from = state.step
    window.setTimeout(() => {
      if (state.step === from) advance()
    }, 180)
  }
}

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

const renderPermission = (request: Ask, more: string) => {
  icon.dataset.kind = 'permission'
  icon.textContent = iconFor(request.event.tool_name)
  kicker.textContent = `${projectOf(request.event)} wants to use${more}`
  const edits = changesFiles(request.event)
  tool.textContent = [request.event.tool_name ?? 'a tool', edits && fileOf(request.event)].filter(Boolean).join(' · ')
  const hunk = hunks.get(request.id) ?? hunkOf(request.event, null)
  if (hunk) renderDiff(detail, hunk)
  else detail.textContent = summarize(request.event.tool_input)
  detail.classList.toggle('diff', Boolean(hunk))
  if (edits && !hunks.has(request.id)) {
    readHunk(request.event).then((full) => {
      if (!full || !state.queue.some(({ id }) => id === request.id)) return
      hunks.set(request.id, full)
      render()
    })
  }
  detail.hidden = false
  actions.hidden = false
  questionList.hidden = true
  footer.hidden = true
}

const renderQuestionStep = (request: Ask, more: string) => {
  const { step } = state
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

const renderPairing = (request: Ask) => {
  icon.dataset.kind = 'permission'
  icon.textContent = '⇄'
  kicker.textContent = 'Wants to pair with this Mac'
  tool.textContent = request.event.device ?? 'iPhone'
  detail.classList.remove('diff')
  detail.textContent = `Code ${request.event.code}. Allow only if your iPhone shows the same code.`
  detail.hidden = false
  actions.hidden = false
  questionList.hidden = true
  footer.hidden = true
}

export const renderPrompt = (request: Ask) => {
  const more = state.queue.length > 1 ? ` · +${state.queue.length - 1} more` : ''
  if (request.kind === 'pair') renderPairing(request)
  else if (request.kind === 'question') renderQuestionStep(request, more)
  else renderPermission(request, more)
}

export const dropStale = (event: HookEvent) => {
  if (event.hook_event_name !== 'UserPromptSubmit' && event.hook_event_name !== 'Stop') return
  const stale = state.queue.filter((request) => request.event.session_id === event.session_id)
  if (stale.length === 0) return
  stale.forEach(({ id }) => {
    invoke('forget', { id })
    remove(id)
  })
  render()
}

export const startPrompts = () => {
  allow.addEventListener('click', () => decide(true))
  deny.addEventListener('click', () => decide(false))
  next.addEventListener('click', advance)
  back.addEventListener('click', () => goTo(state.step - 1))

  listen<Ask>('ask', ({ payload }) => {
    state.queue = [...state.queue, payload]
    setMood('needs')
    render()
  })

  const close = ({ payload }: { payload: number }) => {
    if (!state.queue.some(({ id }) => id === payload)) return
    remove(payload)
    setMood('thinking')
    render()
  }
  listen<number>('expired', close)
  listen<number>('resolved', close)
}
