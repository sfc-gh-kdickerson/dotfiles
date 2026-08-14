#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

STATE_FILE="/tmp/sketchybar_ai_spend_popup_items"

# Treat a failed or malformed fetch as "unknown", not as $0 — a fetch failure and zero
# spend must not look the same on the bar. (No `timeout` wrapper here — not present on
# stock macOS; once ai_spend_fetch.sh calls a real network/DB query, bound it there,
# e.g. with `gtimeout` from `brew install coreutils`.)
if ! SPEND_JSON="$("$PLUGIN_DIR/ai_spend_fetch.sh")" || ! echo "$SPEND_JSON" | jq -e . >/dev/null 2>&1; then
	sketchybar --set "$NAME" label="n/a"
	sketchybar --set ai_spend.week label="n/a"
	exit 0
fi

DAILY_TOTAL="$(echo "$SPEND_JSON" | jq -r '.daily.total_usd // "null"')"
WEEKLY_TOTAL="$(echo "$SPEND_JSON" | jq -r '.weekly.total_usd // "null"')"

if [ "$DAILY_TOTAL" = "null" ] || [ "$WEEKLY_TOTAL" = "null" ]; then
	sketchybar --set "$NAME" label="n/a"
	sketchybar --set ai_spend.week label="n/a"
	exit 0
fi

sketchybar --set "$NAME" label="$(printf '$%.2f' "$DAILY_TOTAL")"
sketchybar --set ai_spend.week label="$(printf '$%.2f' "$WEEKLY_TOTAL")"

# Rebuild the popup breakdown from scratch since the model set can change between refreshes.
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
	local item_name="$1" label_text="$2"
	sketchybar --add item "$item_name" "popup.$NAME" \
		--set "$item_name" label="$label_text" label.color="$LABEL_COLOR" label.font="$FONT:Regular:12.0"
	echo "$item_name" >>"$STATE_FILE"
}

add_header "popup.ai_spend.header_today" "Today"
while IFS=$'\t' read -r model cost; do
	[ -n "$model" ] || continue
	add_row "popup.ai_spend.today.$(sanitize "$model")" "$(printf '%s — $%.2f' "$model" "$cost")"
done < <(echo "$SPEND_JSON" | jq -r '.daily.by_model | to_entries[] | [.key, .value] | @tsv')

add_header "popup.ai_spend.header_week" "This week"
while IFS=$'\t' read -r model cost; do
	[ -n "$model" ] || continue
	add_row "popup.ai_spend.week.$(sanitize "$model")" "$(printf '%s — $%.2f' "$model" "$cost")"
done < <(echo "$SPEND_JSON" | jq -r '.weekly.by_model | to_entries[] | [.key, .value] | @tsv')
