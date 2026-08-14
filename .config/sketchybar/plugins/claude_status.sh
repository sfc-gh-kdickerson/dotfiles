#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

STATE_FILE="/tmp/sketchybar_claude_status_popup_items"

# A fetch failure ("error":true, e.g. `claude` missing/erroring) is "unknown", not
# "zero" — mirrors how ai_spend.sh treats a failed fetch as "n/a" rather than $0.00.
if ! STATUS_JSON="$("$PLUGIN_DIR/claude_status_fetch.sh")" || ! echo "$STATUS_JSON" | jq -e . >/dev/null 2>&1; then
	sketchybar --set "$NAME" icon.color="$THM_OVERLAY_0" label.drawing=on label="n/a"
	exit 0
fi

if [ "$(echo "$STATUS_JSON" | jq -r '.error')" = "true" ]; then
	sketchybar --set "$NAME" icon.color="$THM_OVERLAY_0" label.drawing=on label="n/a"
	exit 0
fi

WAITING_COUNT="$(echo "$STATUS_JSON" | jq '.waiting | length')"
IDLE_COUNT="$(echo "$STATUS_JSON" | jq '.idle | length')"

# Main item: icon color + label carry the signal, icon glyph never reshapes (mirrors
# aerospace.sh recoloring the workspace number without ever swapping its glyph).
# Label color always stays neutral ($LABEL_COLOR) — the waiting/idle distinction
# lives in the words, not the color, per the repo's "icons carry accent, labels
# stay neutral" convention.
if [ "$WAITING_COUNT" -gt 0 ]; then
	LABEL="$WAITING_COUNT waiting"
	[ "$IDLE_COUNT" -gt 0 ] && LABEL="$LABEL · $IDLE_COUNT idle"
	sketchybar --set "$NAME" icon.color="$THM_RED" label.color="$LABEL_COLOR" label.drawing=on label="$LABEL"
elif [ "$IDLE_COUNT" -gt 0 ]; then
	sketchybar --set "$NAME" icon.color="$THM_YELLOW" label.color="$LABEL_COLOR" label.drawing=on label="$IDLE_COUNT idle"
else
	sketchybar --set "$NAME" icon.color="$THM_OVERLAY_0" label.drawing=off
fi

# Rebuild the popup from scratch since the session set can change between refreshes
# (mirrors ai_spend.sh's remove-then-rebuild-from-state-file pattern exactly).
if [ -f "$STATE_FILE" ]; then
	while IFS= read -r old_item; do
		[ -n "$old_item" ] && sketchybar --remove "$old_item" >/dev/null 2>&1
	done <"$STATE_FILE"
fi
: >"$STATE_FILE"

sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

add_header() {
	local item_name="$1" label_text="$2"
	sketchybar --add item "$item_name" "popup.$NAME" \
		--set "$item_name" label="$label_text" label.color="$THM_SUBTEXT_0" label.font="$FONT:Bold:12.0"
	echo "$item_name" >>"$STATE_FILE"
}

add_row() {
	local item_name="$1" label_text="$2" row_color="$3" session="$4" window="$5" pane="$6"
	# Real tmux session names on this machine contain spaces ("dev config", "prod
	# docs") — %q-quote before baking them into click_script, or the jump helper
	# will silently mis-target.
	local jump_cmd
	jump_cmd="$(printf '%q %q %q %q' "$PLUGIN_DIR/claude_jump.sh" "$session" "$window" "$pane")"
	sketchybar --add item "$item_name" "popup.$NAME" \
		--set "$item_name" label="$label_text" label.color="$LABEL_COLOR" label.font="$FONT:Regular:12.0" \
		icon="●" icon.color="$row_color" \
		click_script="$jump_cmd"
	echo "$item_name" >>"$STATE_FILE"
}

if [ "$WAITING_COUNT" -gt 0 ]; then
	add_header "popup.claude_status.header_waiting" "Waiting on you"
	while IFS=$'\t' read -r name cwd_base waiting_for session window pane session_id; do
		[ -n "$name" ] || continue
		label="$(printf '%s — %s (%s)' "$name" "$cwd_base" "$waiting_for")"
		add_row "popup.claude_status.w.$(sanitize "$session_id")" "$label" "$THM_RED" "$session" "$window" "$pane"
	done < <(echo "$STATUS_JSON" | jq -r '.waiting[] | [.name, .cwd_base, .waiting_for, .session, .window, .pane, .session_id] | @tsv')
fi

if [ "$IDLE_COUNT" -gt 0 ]; then
	add_header "popup.claude_status.header_idle" "Idle (finished)"
	while IFS=$'\t' read -r name cwd_base session window pane session_id; do
		[ -n "$name" ] || continue
		label="$(printf '%s — %s' "$name" "$cwd_base")"
		add_row "popup.claude_status.i.$(sanitize "$session_id")" "$label" "$THM_YELLOW" "$session" "$window" "$pane"
	done < <(echo "$STATUS_JSON" | jq -r '.idle[] | [.name, .cwd_base, .session, .window, .pane, .session_id] | @tsv')
fi
