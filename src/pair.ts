import { invoke } from '@tauri-apps/api/core'
import './styles/pair.css'

const code = document.getElementById('code')!
const copy = document.getElementById('copy')!
const notify = document.getElementById('notify') as HTMLInputElement
const steps = document.getElementById('steps')!
const topic = document.getElementById('topic')!

const showTopic = (name: string) => {
  notify.checked = name !== ''
  steps.hidden = name === ''
  topic.textContent = name
}

invoke<string>('pairing_code')
  .then((svg) => { code.innerHTML = svg })
  .catch((error) => { code.textContent = String(error) })

invoke<string>('ntfy_topic').then(showTopic)

notify.addEventListener('change', async () => {
  showTopic(await invoke<string>('set_notifications', { on: notify.checked }))
})

topic.addEventListener('click', async () => {
  const name = topic.textContent ?? ''
  await navigator.clipboard.writeText(name)
  topic.textContent = 'Copied'
  setTimeout(() => { topic.textContent = name }, 1500)
})

copy.addEventListener('click', async () => {
  await navigator.clipboard.writeText(await invoke<string>('pairing_text'))
  copy.textContent = 'Copied'
  setTimeout(() => { copy.textContent = 'Copy pairing code' }, 1500)
})
