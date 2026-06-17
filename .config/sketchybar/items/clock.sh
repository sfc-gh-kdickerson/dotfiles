#!/usr/bin/env bash

COLOR="$THM_MAUVE"

sketchybar --add item clock right \
	--set clock update_freq=1 \
	icon.padding_left=10 \
	icon.color="$COLOR" \
	icon="" \
	label.color="$LABEL_COLOR" \
	label.padding_right=5 \
	label.width=99 \
	align=center \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=2 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.drawing=off \
	script="$PLUGIN_DIR/clock.sh"
