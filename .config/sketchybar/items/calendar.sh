#!/usr/bin/env bash

COLOR="$THM_BLUE"

sketchybar --add item calendar right \
	--set calendar update_freq=15 \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	label.color="$LABEL_COLOR" \
	label.padding_right=$RIGHT_ITEM_PADDING_RIGHT \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.drawing=off \
	script="$PLUGIN_DIR/calendar.sh"
