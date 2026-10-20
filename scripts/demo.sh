#!/bin/sh
set -e
url=http://127.0.0.1:47831/event
dir=$(mktemp -d)/demo
mkdir -p "$dir/src"
file="$dir/src/invoice.ts"
cat > "$file" <<'EOF'
import { Item } from './types'

const TVA = 0.196

export function total(items: Item[]) {
  const sum = items.reduce((s, i) => s + i.price, 0)
  return sum * (1 + TVA)
}
EOF

send() {
  curl -s -m "${2:-5}" -X POST "$url" -d "{\"session_id\":\"demo\",\"cwd\":\"$dir\",\"transcript_path\":\"/demo\",$1}" > /dev/null || true
}

step() {
  echo "$1"
  sleep "${2:-2.5}"
}

send '"hook_event_name":"SessionStart"'
send '"hook_event_name":"UserPromptSubmit","prompt":"update the vat rate"'
step "thinking"
send "\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$file\"}"
step "reading"
send "\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$file\",\"old_string\":\"const TVA = 0.196\",\"new_string\":\"const TVA = 0.20 // 2026\"}"
sed -i '' 's|const TVA = 0.196|const TVA = 0.20 // 2026|' "$file"
step "edit diff" 4
send "\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"}"
step "running tests" 3
send "\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$file\",\"old_string\":\"  return sum * (1 + TVA)\",\"new_string\":\"  return Math.round(sum * (1 + TVA) * 100) / 100\"}" 4 &
step "permission prompt (Allow/Deny)" 5
send '"hook_event_name":"UserPromptSubmit","prompt":"skip that"'
send '"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Round totals to cents?","options":[{"label":"Yes (Recommended)"},{"label":"No"}]}]}' 4 &
step "question" 5
send '"hook_event_name":"Stop"'
step "done" 4
send '"hook_event_name":"SessionEnd"'
rm -rf "$(dirname "$dir")"
