#!/usr/bin/env bash
# Fetches active Claude Code sessions via `claude agents --json`, correlates each
# interactive waiting/idle session's pid to the tmux pane it's running in, and
# prints one JSON object:
#   {"waiting":[{name,cwd_base,status,waiting_for,session,window,pane,session_id}, ...],
#    "idle":[...same shape, waiting_for:null...],
#    "error": bool}
# `error:true` means the fetch itself failed (claude missing/errored) — the caller
# must treat that as "unknown", not "zero". A legitimately empty tmux server or zero
# matching sessions is `error:false` with empty arrays.
set -uo pipefail # not -e: a single correlation miss must not abort the whole script

# claude lives in ~/.local/bin, which is off sketchybar's restricted PATH.
CLAUDE_BIN="/Users/kdickerson/.local/bin/claude"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"

if [ -z "$CLAUDE_BIN" ] || ! AGENTS_JSON="$("$CLAUDE_BIN" agents --json 2>/dev/null)" ||
	! echo "$AGENTS_JSON" | jq -e . >/dev/null 2>&1; then
	echo '{"waiting":[],"idle":[],"error":true}'
	exit 0
fi

# NB: tab is a shell "blank" IFS character, so `read` silently collapses runs of
# consecutive tabs (i.e. empty fields) instead of preserving them as empty — a
# classic IFS=tab gotcha. `waitingFor` is legitimately absent for idle sessions, so
# an empty-string sentinel (U+2205, EMPTY SET) stands in for it here and is mapped
# back to `null` in the final jq pass below, keeping every TSV field non-empty.
EMPTY_SENTINEL=$'∅'
CANDIDATES="$(echo "$AGENTS_JSON" | jq -r --arg empty "$EMPTY_SENTINEL" '
  .[] | select(.kind=="interactive" and (.status=="waiting" or .status=="idle"))
  | [.pid, .status, (.waitingFor // $empty), .name, .cwd, .sessionId]
  | @tsv
')"

if [ -z "$CANDIDATES" ]; then
	echo '{"waiting":[],"idle":[],"error":false}'
	exit 0
fi

# pid -> ppid map, built once. `=` suffixes on ps field names suppress the header
# row on macOS/BSD ps.
declare -A PPID_OF
while read -r pid ppid; do
	PPID_OF["$pid"]="$ppid"
done < <(ps -axo pid=,ppid=)

# pane_pid -> "session\twindow\tpane", built once. Four separate tab-delimited
# fields rather than a compound "session:window.pane" string — session names on
# this machine contain spaces and could in principle contain ':' or '.', which
# would make a compound string ambiguous to re-parse.
declare -A TARGET_OF_PANEPID
if PANES="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}' 2>/dev/null)"; then
	while IFS=$'\t' read -r sess win pane panepid; do
		[ -n "$panepid" ] || continue
		TARGET_OF_PANEPID["$panepid"]="$sess"$'\t'"$win"$'\t'"$pane"
	done <<<"$PANES"
fi
# No tmux server running -> TARGET_OF_PANEPID stays empty, every candidate fails to
# correlate and gets dropped below. That's a legitimate empty result, not an error.

resolve_target() {
	local pid="$1" hops=0
	while [ -n "$pid" ] && [ "$hops" -lt 20 ]; do
		if [ -n "${TARGET_OF_PANEPID[$pid]+x}" ]; then
			printf '%s\n' "${TARGET_OF_PANEPID[$pid]}"
			return 0
		fi
		pid="${PPID_OF[$pid]:-}"
		hops=$((hops + 1))
	done
	return 1
}

clean() { tr -d '\t\n' <<<"$1"; }

RESOLVED=""
while IFS=$'\t' read -r pid status waiting_for name cwd session_id; do
	target="$(resolve_target "$pid")" || continue
	IFS=$'\t' read -r tsess twin tpane <<<"$target"
	cwd_base="$(basename "$cwd")"
	RESOLVED+="$(clean "$status")"$'\t'"$(clean "$name")"$'\t'"$(clean "$cwd_base")"$'\t'
	RESOLVED+="$(clean "$waiting_for")"$'\t'"$tsess"$'\t'"$twin"$'\t'"$tpane"$'\t'"$session_id"$'\n'
done <<<"$CANDIDATES"

printf '%s' "$RESOLVED" | jq -R -s --arg empty "$EMPTY_SENTINEL" '
  [splits("\n") | select(length > 0) | split("\t")]
  | map({
      status: .[0], name: .[1], cwd_base: .[2],
      waiting_for: (.[3] | if . == $empty then null else . end),
      session: .[4], window: (.[5] | tonumber), pane: (.[6] | tonumber),
      session_id: .[7]
    })
  | { waiting: (map(select(.status=="waiting"))),
      idle:    (map(select(.status=="idle"))),
      error: false }
'
