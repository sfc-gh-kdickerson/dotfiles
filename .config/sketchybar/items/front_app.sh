#!/usr/bin/env bash

COLOR="$THM_BLUE"

# gap before front_app (sits between the spaces island and the app island)
sketchybar --add item spc.left left \
	--set spc.left icon.drawing=off label.drawing=off background.drawing=off

# Static leading glyph (nf-fa-window_maximize). Swap to any Nerd Font glyph you like.
sketchybar \
	--add item front_app left \
	--set front_app script="$PLUGIN_DIR/front_app.sh" \
	icon="" \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	icon.padding_right=4 \
	label.color="$LABEL_COLOR" \
	label.padding_left=0 \
	label.padding_right=10 \
	background.drawing=on \
	background.color="$ISLAND_BG" \
	background.corner_radius="$ISLAND_RADIUS" \
	background.height="$ISLAND_HEIGHT" \
	background.border_width="$ISLAND_BORDER_WIDTH" \
	background.border_color="$ISLAND_BORDER_COLOR" \
	background.shadow.drawing="$ISLAND_SHADOW" \
	background.shadow.color="$ISLAND_SHADOW_COLOR" \
	background.shadow.distance="$ISLAND_SHADOW_DISTANCE" \
	background.shadow.angle="$ISLAND_SHADOW_ANGLE" \
	associated_display=active \
	--subscribe front_app front_app_switched
