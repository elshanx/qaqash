import { tabs } from './dom'
import { render } from './island'
import { state } from './state'

export type Tab = 'home' | 'sessions' | 'settings'

export const renderTabs = () => {
  tabs.querySelectorAll<HTMLElement>('[data-tab]').forEach((button) => {
    button.toggleAttribute('data-active', button.dataset.tab === state.tab)
  })
}

export const startTabs = () => {
  tabs.querySelectorAll<HTMLElement>('[data-tab]').forEach((button) => {
    button.addEventListener('click', () => {
      state.tab = button.dataset.tab as Tab
      render()
    })
  })
}
