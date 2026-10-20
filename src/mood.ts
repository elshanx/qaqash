import { island } from './dom'
import { state } from './state'
import type { Mood } from './types'

let restTimer = 0

export const showCompactMusic = () => {
  island.toggleAttribute('data-music', Boolean(state.track?.playing) && island.dataset.mood !== 'needs')
}

export const setMood = (mood: Mood) => {
  clearTimeout(restTimer)
  island.dataset.mood = state.queue.length > 0 ? 'needs' : mood
  showCompactMusic()
  if (island.dataset.mood === 'done') restTimer = window.setTimeout(() => setMood('idle'), 4000)
}
