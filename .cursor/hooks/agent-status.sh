#!/usr/bin/env bash
# Cursor Agent CLI only — pane status + a tiny chat snapshot for tmux-picker.
# Desktop Cursor is ignored (find_cursor_pid walks to cursor-agent / agent CLI).
#
# sessionStart, stop          → ready
# beforeSubmitPrompt          → busy + last user prompt
# preToolUse                  → last tool name (busy context)
# afterAgentResponse          → last assistant text
# sessionEnd                  → remove the pane's status file
#
# In a Rex pane (REX_BLOCK set, not inside tmux) it also reports OSC 7501 program
# status to the agent's terminal and records the pane's conversation for rex-snapshot.
#
# State: $XDG_STATE_HOME/tmux-picker-agents/<pane-id-without-%>.json
# Join key is TMUX_PANE (%N), same as tmux-picker's pane target.
# kind=cursor routes the row to .config/tmux-picker/agents/cursor.lua.
# conversation_id joins ~/.config/cursor/chats/*/<id>/meta.json for the title.

set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/go/bin:${HOME}/.nix-profile/bin:${PATH:-/usr/bin}"

PID_LIB="${HOME}/.tmux/plugins/tmux-assistant-resurrect/hooks/lib-cursor-pid.sh"
[ -f "$PID_LIB" ] || exit 0
# shellcheck source=/dev/null
source "$PID_LIB"

command -v jq >/dev/null 2>&1 || exit 0

CURSOR_PID=$(find_cursor_pid || true)

STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux-picker-agents"
INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null) || exit 0

pane_file() {
  pane="$1"
  pane="${pane#%}"
  [ -n "$pane" ] || return 1
  printf '%s/%s.json' "$STATE_DIR" "$pane"
}

# Agent pid must sit under the pane's shell (child, not ancestor).
pane_owns_pid() {
  pane="$1"
  pid="$2"
  pane_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null | tr -d ' ') || return 1
  [ -n "$pane_pid" ] && [ -n "$pid" ] || return 1
  case "$pane_pid:$pid" in
    *[!0-9:]* | 0:* | *:0) return 1 ;;
  esac
  p="$pid"
  i=0
  while [ "$p" -gt 1 ] && [ "$i" -lt 8 ]; do
    [ "$p" = "$pane_pid" ] && return 0
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    case "$p" in
      '' | *[!0-9]*) return 1 ;;
    esac
    i=$((i + 1))
  done
  return 1
}

remove_by_pane() {
  [ -n "${TMUX_PANE:-}" ] || return 0
  f=$(pane_file "$TMUX_PANE") && rm -f "$f" 2>/dev/null || true
}

remove_by_pid() {
  [ -n "${CURSOR_PID:-}" ] || return 0
  [ -d "$STATE_DIR" ] || return 0
  for f in "$STATE_DIR"/*.json; do
    [ -f "$f" ] || continue
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null) || continue
    [ "$pid" = "$CURSOR_PID" ] && rm -f "$f"
  done
}

# Rex shows OSC 7501 program status on tabs and in the session picker. The hook's
# stdout belongs to the agent, so write the report to the agent's own terminal.
rex_report() {
  [ -n "${REX_BLOCK:-}" ] && [ -z "${TMUX:-}" ] && [ -n "$CURSOR_PID" ] || return 0
  tty=$(ps -o tty= -p "$CURSOR_PID" 2>/dev/null | tr -d ' ')
  case "$tty" in
    '' | '?' | *[!a-z0-9/]*) return 0 ;;
  esac
  [ -w "/dev/$tty" ] || return 0
  body="state=$1:app=cursor"
  if [ -n "${2:-}" ]; then
    msg=$(jq -rn --arg s "$2" '$s | gsub("[\\u0000-\\u001f\\u007f-\\u009f]"; " ") | .[0:160] | @base64') || msg=""
    [ -n "$msg" ] && body="$body:msg=$msg"
  fi
  printf '\033]7501;%s\033\\' "$body" >"/dev/$tty" 2>/dev/null || true
}

case "$EVENT" in
  sessionStart) rex_report idle ;;
  beforeSubmitPrompt) rex_report working "$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)" ;;
  preToolUse) rex_report working "$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)" ;;
  stop)
    case "$(printf '%s' "$INPUT" | jq -r '.status // ""' 2>/dev/null)" in
      aborted) rex_report idle ;;
      error) rex_report error "Agent stopped with an error" ;;
      *) rex_report done "Agent finished" ;;
    esac
    ;;
  sessionEnd) rex_report clear ;;
esac

# rex-snapshot resumes the conversation a Rex pane's agent was running.
REX_AGENTS="${XDG_STATE_HOME:-${HOME}/.local/state}/rex-agents"
if [ -n "${REX_BLOCK:-}" ]; then
  rex_agent_file="$REX_AGENTS/${REX_BLOCK#block:}.json"
  conversation=$(printf '%s' "$INPUT" | jq -r '.conversation_id // .session_id // ""' 2>/dev/null) || conversation=""
  if [ "$EVENT" = sessionEnd ]; then
    rm -f "$rex_agent_file"
  elif [ -n "$CURSOR_PID" ] && [ -n "$conversation" ] \
    && { [ "$EVENT" = sessionStart ] || [ "$EVENT" = beforeSubmitPrompt ]; }; then
    mkdir -p "$REX_AGENTS" 2>/dev/null || true
    jq -n --arg block "$REX_BLOCK" --arg conversation "$conversation" --argjson pid "$CURSOR_PID" \
      '{block: $block, conversation_id: $conversation, pid: $pid}' >"$rex_agent_file.tmp" 2>/dev/null \
      && mv "$rex_agent_file.tmp" "$rex_agent_file" || rm -f "$rex_agent_file.tmp"
  fi
fi

# sessionEnd must run even when the CLI pid walk fails (hard-kill, dying parent).
if [ "$EVENT" = sessionEnd ]; then
  remove_by_pane
  remove_by_pid
  exit 0
fi

[ -n "$CURSOR_PID" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0
pane_owns_pid "$TMUX_PANE" "$CURSOR_PID" || exit 0

# Merge a patch into the pane file. $1 = ready|busy|"" (empty keeps status).
apply_patch() {
  status="$1"
  [ -n "${TMUX_PANE:-}" ] || exit 0
  mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
  chmod 700 "$STATE_DIR" 2>/dev/null || true
  dest=$(pane_file "$TMUX_PANE") || exit 0
  old="{}"
  [ -f "$dest" ] && old=$(cat "$dest" 2>/dev/null || echo '{}')
  tmp=$(mktemp "${STATE_DIR}/.tmp.XXXXXX") || exit 0
  if ! printf '%s\n%s\n' "$old" "$INPUT" | jq -s \
      --arg status "$status" \
      --arg pane "$TMUX_PANE" \
      --argjson pid "$CURSOR_PID" \
      --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg event "$EVENT" \
      '
      .[0] as $old | .[1] as $in |
      $old
      + {kind: "cursor", pane_id: $pane, pid: $pid, updated: $updated}
      + (if $status != "" then {status: $status} else {} end)
      + (if ($in.model // "") != "" then {model: $in.model} else {} end)
      + (if ($in.conversation_id // $in.session_id // "") != "" then
           {conversation_id: ($in.conversation_id // $in.session_id)}
         else {} end)
      + (if $event == "beforeSubmitPrompt" then
           {prompt: (($in.prompt // "") | .[0:2000]), tool: ""}
         else {} end)
      + (if $event == "afterAgentResponse" then
           {response: (($in.text // "") | .[0:4000])}
         else {} end)
      + (if $event == "preToolUse" then
           {tool: ($in.tool_name // "")}
         else {} end)
      + (if $event == "stop" then
           {stop_status: ($in.status // ""), tool: ""}
         else {} end)
      ' >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    exit 0
  fi
  mv "$tmp" "$dest"
}

case "$EVENT" in
  sessionStart) apply_patch ready ;;
  beforeSubmitPrompt) apply_patch busy ;;
  preToolUse) apply_patch busy ;;
  afterAgentResponse) apply_patch "" ;;
  stop) apply_patch ready ;;
esac

exit 0
