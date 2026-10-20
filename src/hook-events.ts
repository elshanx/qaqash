import type { HookEvent, Mood } from './types'

const activities: Record<string, string> = {
  Bash: 'Running',
  Read: 'Reading',
  Edit: 'Editing',
  Write: 'Writing',
  NotebookEdit: 'Editing',
  Grep: 'Searching',
  Glob: 'Searching',
  WebFetch: 'Browsing',
  WebSearch: 'Searching',
  Task: 'Delegating',
  Agent: 'Delegating',
  AskUserQuestion: 'Asking',
  TodoWrite: 'Planning',
}

export const describe = (event: HookEvent): string => {
  switch (event.hook_event_name) {
    case 'SessionStart': return 'Ready'
    case 'SessionEnd': return 'Ended'
    case 'UserPromptSubmit': return 'Thinking…'
    case 'PreToolUse': return activities[event.tool_name ?? ''] ?? 'Working…'
    case 'Notification': return event.message ?? 'Needs you'
    case 'PermissionRequest': return 'Needs you'
    case 'Stop': return 'Done'
    default: return event.hook_event_name
  }
}

const moods: Record<string, Mood> = {
  UserPromptSubmit: 'thinking',
  PreToolUse: 'thinking',
  Notification: 'needs',
  Stop: 'done',
}

export const moodOf = (event: HookEvent): Mood => moods[event.hook_event_name] ?? 'thinking'

export const projectOf = (event: HookEvent): string =>
  event.cwd?.split('/').pop() || event.session_id?.slice(0, 8) || 'Claude'

export const summarize = (input: Record<string, unknown> = {}): string =>
  String(input.command ?? input.file_path ?? input.url ?? JSON.stringify(input, null, 2))
