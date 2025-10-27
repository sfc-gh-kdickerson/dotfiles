#!/usr/bin/env bash

COLOR="$THM_RED"

sketchybar --add item calevent right \
	--set calevent update_freq=60 \
	label.max_chars=34 \
	scroll_texts=on \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	label.color="$COLOR" \
	label.padding_right=$RIGHT_ITEM_PADDING_RIGHT \
    label.font.size=11 \
    label.scroll_duration=300 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.drawing=on \
	script="$PLUGIN_DIR/events.sh" \
    background.color="$ITEM_BG_COLOR"

sketchybar --subscribe calevent mouse.clicked
