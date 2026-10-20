import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { artist, elapsed, island, miniPlayer, miniTitle, miniToggle, player, progress, remaining, title, toggle } from './dom'
import { render } from './island'
import { showCompactMusic } from './mood'
import { state } from './state'
import type { Track } from './types'

let musicAppArtwork: string | null = null
let currentCover: string | null = null

const hueOf = (text: string) => [...text].reduce((hash, char) => (hash * 31 + char.charCodeAt(0)) % 360, 7)

const spotifyCover = (url = ''): string | null => {
  try {
    const parsed = new URL(url)
    return parsed.protocol === 'https:' && parsed.hostname === 'i.scdn.co' ? parsed.href : null
  } catch {
    return null
  }
}

const vivid = (red: number, green: number, blue: number): string => {
  const [r, g, b] = [red / 255, green / 255, blue / 255]
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const delta = max - min
  const hue = delta === 0 ? 0
    : max === r ? 60 * (((g - b) / delta) % 6)
    : max === g ? 60 * ((b - r) / delta + 2)
    : 60 * ((r - g) / delta + 4)
  const lightness = (max + min) / 2
  const saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1))
  const keepGrey = saturation < 0.12
  return `hsl(${Math.round((hue + 360) % 360)} ${keepGrey ? 0 : Math.max(55, saturation * 100)}% ${Math.min(72, Math.max(58, lightness * 100))}%)`
}

const tintFrom = (url: string) => {
  const image = new Image()
  image.crossOrigin = 'anonymous'
  image.onload = () => {
    const size = 12
    const canvas = Object.assign(document.createElement('canvas'), { width: size, height: size })
    const context = canvas.getContext('2d')
    if (!context) return
    context.drawImage(image, 0, 0, size, size)
    let pixels: Uint8ClampedArray
    try {
      pixels = context.getImageData(0, 0, size, size).data
    } catch {
      return
    }
    let red = 0
    let green = 0
    let blue = 0
    let total = 0
    for (let index = 0; index < pixels.length; index += 4) {
      const [r, g, b] = [pixels[index], pixels[index + 1], pixels[index + 2]]
      const max = Math.max(r, g, b)
      const weight = ((max - Math.min(r, g, b)) * max) / 255 + 1
      red += r * weight
      green += g * weight
      blue += b * weight
      total += weight
    }
    if (currentCover === url) island.style.setProperty('--tint', vivid(red / total, green / total, blue / total))
  }
  image.src = url
}

const paintArtwork = () => {
  const { track } = state
  const cover = musicAppArtwork ?? spotifyCover(track?.artworkUrl)
  currentCover = cover
  document.querySelectorAll<HTMLElement>('.art').forEach((element) => {
    element.style.setProperty('--hue', String(hueOf(track?.album ?? '')))
    if (cover) element.style.setProperty('--art', `url("${cover}")`)
    else element.style.removeProperty('--art')
  })
  island.style.setProperty('--tint', `hsl(${hueOf(track?.album ?? '')} 75% 65%)`)
  if (cover) tintFrom(cover)
}

const clock = (totalSeconds: number) => {
  const whole = Math.max(0, Math.floor(totalSeconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}

const updateProgress = () => {
  const { track } = state
  if (!track) return
  const playedFor = track.playing ? (Date.now() - state.trackSyncedAt) / 1000 : 0
  const position = Math.min(track.position + playedFor, track.duration)
  elapsed.textContent = clock(position)
  remaining.textContent = `-${clock(track.duration - position)}`
  progress.style.setProperty('--progress', String(track.duration ? position / track.duration : 0))
}

const idle = { app: 'Spotify', playing: false, title: 'Spotify', artist: 'Not playing', duration: 0 } as const

export const renderPlayer = () => {
  const track = state.track ?? idle
  miniTitle.textContent = [track.title, track.artist].filter(Boolean).join(' · ')
  miniToggle.toggleAttribute('data-playing', track.playing)
  title.textContent = track.title
  artist.textContent = track.artist
  progress.parentElement!.hidden = track.duration === 0
  toggle.toggleAttribute('data-playing', track.playing)
  player.toggleAttribute('data-playing', track.playing)
  player.toggleAttribute('data-idle', !state.track)
  if (state.track) updateProgress()
}

const albumKey = (playing: Track | null) => (playing ? `${playing.app}:${playing.album}` : '')

const loadArtwork = async () => {
  const bytes = state.track?.app === 'Music' ? await invoke<number[] | null>('music_artwork') : null
  if (musicAppArtwork) URL.revokeObjectURL(musicAppArtwork)
  musicAppArtwork = bytes ? URL.createObjectURL(new Blob([new Uint8Array(bytes)])) : null
  paintArtwork()
}

export const startMusic = () => {
  listen<Track | null>('music', ({ payload }) => {
    const wasShown = Boolean(state.track)
    const albumChanged = albumKey(state.track) !== albumKey(payload)
    state.track = payload
    state.trackSyncedAt = Date.now()
    if (albumChanged) loadArtwork()
    showCompactMusic()
    if (!player.hidden || !miniPlayer.hidden) renderPlayer()
    if (state.hovering && wasShown !== Boolean(state.track)) render()
  })

  document.querySelectorAll<HTMLElement>('#player [data-open-source], #mini-player [data-open-source]').forEach((element) => {
    element.addEventListener('click', () => {
      invoke('music_control', { player: state.track?.app ?? idle.app, action: 'open' })
    })
  })

  document.querySelectorAll<HTMLButtonElement>('#controls button, #mini-toggle').forEach((button) => {
    button.addEventListener('click', async () => {
      const { track } = state
      const action = button.dataset.action
      await invoke('music_control', { player: track?.app ?? idle.app, action })
      if (track && action === 'toggle') {
        state.track = { ...track, playing: !track.playing, position: track.position + (track.playing ? (Date.now() - state.trackSyncedAt) / 1000 : 0) }
        state.trackSyncedAt = Date.now()
        showCompactMusic()
        renderPlayer()
      }
    })
  })

  setInterval(() => {
    if (!player.hidden) updateProgress()
  }, 500)
}
