import { invoke } from '@tauri-apps/api/core'
import { settingsPage, soundButton } from './dom'
import { render } from './island'

type Settings = { sound: boolean, quiet: boolean, editPanel: boolean }

const labels: Record<keyof Settings, string> = {
  sound: 'Sounds',
  editPanel: 'Show edits while Claude works',
  quiet: 'Stay quiet while the Claude app is in front',
}

const load = (): Settings => {
  const defaults = { sound: true, quiet: true, editPanel: true }
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

export const renderSettings = () => {
  settingsPage.replaceChildren(...(Object.keys(labels) as (keyof Settings)[]).map(settingRow))
}

export const startSettings = () => {
  soundButton.addEventListener('click', () => toggle('sound'))
  apply()
}
