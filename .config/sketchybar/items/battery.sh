#!/usr/bin/env bash

COLOR="$THM_SKY"

sketchybar --add item battery right \
	--set battery \
	update_freq=60 \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	label.padding_right=$RIGHT_ITEM_PADDING_RIGHT \
	label.color="$COLOR" \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.drawing=on \
	background.color="$ITEM_BG_COLOR" \
	script="$PLUGIN_DIR/power.sh" \
	--subscribe battery power_source_change
