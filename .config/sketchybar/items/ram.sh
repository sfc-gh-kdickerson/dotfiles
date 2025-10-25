#!/usr/bin/env bash

COLOR="$THM_YELLOW"

sketchybar --add item ram right \
	--set ram \
	update_freq=60 \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	label.color="$COLOR" \
	label.padding_right=$RIGHT_ITEM_PADDING_RIGHT \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.drawing=on \
	script="$PLUGIN_DIR/ram.sh" \
	background.color="$ITEM_BG_COLOR" \
