#!/usr/bin/env bash

COLOR="$THM_SKY"

# gap before this island (sits between sysisland and timeisland)
sketchybar --add item spc.time right \
	--set spc.time icon.drawing=off label.drawing=off background.drawing=off width="$ISLAND_GAP"

sketchybar \
	--add item sound right \
	--set sound \
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
	script="$PLUGIN_DIR/sound.sh" \
	--subscribe sound volume_change
