export type HookEvent = {
  hook_event_name: string
  session_id?: string
  cwd?: string
  transcript_path?: string
  tool_name?: string
  tool_input?: Record<string, unknown>
  message?: string
  qaqash_pid?: number
}

export type Question = {
  question: string
  options: { label: string }[]
  multiSelect?: boolean
}

export type Track = {
  app: 'Spotify' | 'Music'
  playing: boolean
  title: string
  artist: string
  album: string
  position: number
  duration: number
  artworkUrl?: string
}

export type Ask = {
  id: number
  kind: 'permission' | 'question' | 'pair'
  event: HookEvent & { device?: string, code?: string }
}

export type Mood = 'idle' | 'thinking' | 'needs' | 'done'

export type Session = { name: string, state: string, mood: Mood, seen: number, pid?: number }
