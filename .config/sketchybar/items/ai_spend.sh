#!/usr/bin/env bash

COLOR_TODAY="$THM_TEAL"
COLOR_WEEK="$THM_MAUVE"

# Explicit gap before this island (front_app's own spacer omits a width, which is why
# spacing next to it has been inconsistent — this one sets it explicitly).
sketchybar --add item spc.ai_spend left \
	--set spc.ai_spend icon.drawing=off label.drawing=off background.drawing=off width=6

# Two chips (today / week), each with its own colored icon, grouped into one shared
# island via the ai_spend_island bracket (added in sketchybarrc after all items exist —
# same convention as sysisland/timeisland). Only the "today" chip polls; its plugin sets
# both chips' labels in one run, so the fetch still only happens once per cycle.
sketchybar --add item ai_spend.today left \
	--set ai_spend.today \
	update_freq=3600 \
	icon=$'' \
	icon.color="$COLOR_TODAY" \
	icon.padding_left=10 \
	icon.padding_right=4 \
	label.color="$LABEL_COLOR" \
	label.padding_right=6 \
	background.drawing=off \
	popup.background.color="$ISLAND_BG" \
	popup.background.corner_radius="$ISLAND_RADIUS" \
	popup.background.border_width=1 \
	popup.background.border_color="$ISLAND_BORDER_COLOR" \
	popup.y_offset=5 \
	script="$PLUGIN_DIR/ai_spend.sh" \
	click_script="sketchybar --set ai_spend.today popup.drawing=toggle"

sketchybar --add item ai_spend.week left \
	--set ai_spend.week \
	icon=$'' \
	icon.color="$COLOR_WEEK" \
	icon.padding_left=6 \
	icon.padding_right=4 \
	label.color="$LABEL_COLOR" \
	label.padding_right=10 \
	background.drawing=off
