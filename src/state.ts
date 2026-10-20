import type { Ask, Session, Track } from './types'

export const state = {
  queue: [] as Ask[],
  step: 0,
  hovering: false,
  lastStatus: 'peep',
  track: null as Track | null,
  trackSyncedAt: 0,
  barHeight: 33,
}

export const picks = new Map<string, string[]>()
export const sessions = new Map<string, Session>()
