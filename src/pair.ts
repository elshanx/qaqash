import { invoke } from '@tauri-apps/api/core'
import './styles/pair.css'

const code = document.getElementById('code')!
const copy = document.getElementById('copy')!

invoke<string>('pairing_code')
  .then((svg) => { code.innerHTML = svg })
  .catch((error) => { code.textContent = String(error) })

copy.addEventListener('click', async () => {
  await navigator.clipboard.writeText(await invoke<string>('pairing_text'))
  copy.textContent = 'Copied'
  setTimeout(() => { copy.textContent = 'Copy pairing code' }, 1500)
})
