import { invoke } from '@tauri-apps/api/core'
import { settingsPage, soundButton } from './dom'
import { render } from './island'

type Settings = { sound: boolean, quiet: boolean, editPanel: boolean, menuBarIcon: boolean }

const labels: Record<keyof Settings, string> = {
  sound: 'Sounds',
  editPanel: 'Show edits while Claude works',
  quiet: 'Stay quiet while the Claude app is in front',
  menuBarIcon: 'Show icon in the menu bar',
}

const load = (): Settings => {
  const defaults = { sound: true, quiet: true, editPanel: true, menuBarIcon: true }
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem('settings') ?? '{}') }
  } catch {
    return defaults
  }
}

export const settings = load()

const apply = () => {
  try {
    localStorage.setItem('settings', JSON.stringify(settings))
  } catch {}
  invoke('set_settings', { sound: settings.sound, quiet: settings.quiet })
  invoke('set_tray_visible', { visible: settings.menuBarIcon })
  soundButton.toggleAttribute('data-off', !settings.sound)
}

const toggle = (key: keyof Settings) => {
  settings[key] = !settings[key]
  apply()
  render()
}

const settingRow = (key: keyof Settings) => {
  const row = Object.assign(document.createElement('button'), { className: 'setting' })
  row.append(Object.assign(document.createElement('span'), { textContent: labels[key] }), Object.assign(document.createElement('span'), { className: 'switch' }))
  row.toggleAttribute('data-on', settings[key])
  row.addEventListener('click', () => toggle(key))
  return row
}

const actionButton = (text: string, command: string) => {
  const button = Object.assign(document.createElement('button'), { className: 'setting-action', textContent: text })
  button.addEventListener('click', () => invoke(command))
  return button
}

export const renderSettings = () => {
  const actions = document.createElement('div')
  actions.className = 'setting-actions'
  actions.append(actionButton('Pair iPhone…', 'pair_iphone'), actionButton('Quit Qaqash', 'quit'))
  settingsPage.replaceChildren(...(Object.keys(labels) as (keyof Settings)[]).map(settingRow), actions)
}

export const startSettings = () => {
  soundButton.addEventListener('click', () => toggle('sound'))
  apply()
}
