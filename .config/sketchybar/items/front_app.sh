#!/usr/bin/env bash

COLOR="$THM_GREEN"

sketchybar --add item seperator left \
	--set seperator update_freq=1 \
	icon.padding_left=10 \
	icon.color="$COLOR" \
	icon="" \
	label.color="$COLOR" \
	label.padding_right=0 

sketchybar \
	--add item front_app left \
	--set front_app script="$PLUGIN_DIR/front_app.sh" \
	icon.drawing=off \
	background.height=26 \
	background.padding_left=0 \
	background.padding_right=0 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.corner_radius="$CORNER_RADIUS" \
	background.color="$ITEM_BG_COLOR" \
	label.color="$COLOR" \
	label.padding_left=$LEFT_ITEM_PADDING_LEFT \
	label.padding_right=8 \
	associated_display=active \
	--subscribe front_app front_app_switched
