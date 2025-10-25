#!/usr/bin/env bash

COLOR="$THM_PEACH"

sketchybar --add item cpu right \
	--set cpu \
	update_freq=5 \
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
	script="$PLUGIN_DIR/cpu.sh" \
	background.color="$ITEM_BG_COLOR" \
