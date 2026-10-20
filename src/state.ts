import type { Activity, Ask, Session, Track } from './types'

export const state = {
  queue: [] as Ask[],
  step: 0,
  hovering: false,
  lastStatus: 'qaqash',
  track: null as Track | null,
  trackSyncedAt: 0,
  barHeight: 33,
  activity: null as Activity | null,
  vscode: null as { file: string, project: string } | null,
}

export const picks = new Map<string, string[]>()
export const sessions = new Map<string, Session>()
