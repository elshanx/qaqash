import { listen } from '@tauri-apps/api/event'
import { render } from './island'
import { state } from './state'
import { refreshVSCode } from './vscode'

let pointer: [number, number] | null = null
let hot: Element | null = null

export const markHot = () => {
  const target = pointer && document.elementFromPoint(...pointer)?.closest('[data-open-source], button')
  if (target === hot) return
  hot?.removeAttribute('data-hot')
  target?.setAttribute('data-hot', '')
  hot = target ?? null
}

export const startHover = () => {
  listen<[number, number] | null>('hover', ({ payload }) => {
    pointer = payload
    markHot()
    if (state.hovering === Boolean(payload)) return
    state.hovering = Boolean(payload)
    render()
    if (state.hovering) refreshVSCode().then(render)
  })
}
