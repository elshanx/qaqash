import { invoke } from '@tauri-apps/api/core'
import { miniVSCode, vscodeCard } from './dom'
import { state } from './state'

export const vscodeId = 'com.microsoft.VSCode'

const parseTitle = (title: string) => {
  const [first, project] = title.replace(/^● /, '').split(' — ')
  return project ? { file: first, project } : { file: '', project: first }
}

export const refreshVSCode = async () => {
  const title = await invoke<string | null>('vscode_window').catch(() => null)
  state.vscode = title ? parseTitle(title) : null
}

const label = () => {
  const { vscode } = state
  if (!vscode) return { title: 'VS Code', sub: 'Not open' }
  return vscode.file ? { title: vscode.file, sub: `${vscode.project} · VS Code` } : { title: vscode.project, sub: 'VS Code' }
}

export const renderVSCode = () => {
  const { title, sub } = label()
  vscodeCard.querySelector('.card-title')!.textContent = title
  vscodeCard.querySelector('.card-sub')!.textContent = sub
  miniVSCode.querySelector('.mini-text')!.textContent = `${title} · ${sub}`
}

export const startVSCode = () => {
  vscodeCard.addEventListener('click', () => invoke('open_vscode'))
  miniVSCode.addEventListener('click', () => invoke('open_vscode'))
}
