import { invoke } from '@tauri-apps/api/core'
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

export const vscodeRow = ({ file, project }: { file: string, project: string }) => {
  const row = document.createElement('li')
  row.dataset.mood = 'vscode'
  row.toggleAttribute('data-open-source', true)
  row.addEventListener('click', () => invoke('open_vscode'))
  row.style.setProperty('--i', '0')
  row.append(Object.assign(document.createElement('span'), { textContent: file || project }))
  row.append(Object.assign(document.createElement('span'), { textContent: file ? `${project} · VS Code` : 'VS Code' }))
  return row
}
