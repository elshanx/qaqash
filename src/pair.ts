import { invoke } from '@tauri-apps/api/core'
import './styles/pair.css'

const code = document.getElementById('code')!
const copy = document.getElementById('copy')!
const nudge = document.getElementById('nudge') as HTMLInputElement

invoke<string>('pairing_code')
  .then((svg) => { code.innerHTML = svg })
  .catch((error) => { code.textContent = String(error) })

invoke<string>('nudge_target').then((target) => { nudge.value = target })

nudge.addEventListener('change', () => invoke('set_nudge_target', { to: nudge.value }))

copy.addEventListener('click', async () => {
  await navigator.clipboard.writeText(await invoke<string>('pairing_text'))
  copy.textContent = 'Copied'
  setTimeout(() => { copy.textContent = 'Copy pairing code' }, 1500)
})
