#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change

for sid in $(aerospace list-workspaces --all); do
    sketchybar --add item space.$sid left \
        --subscribe space.$sid aerospace_workspace_change \
        --set space.$sid \
        background.color="$COMMENT" \
	    background.corner_radius="$CORNER_RADIUS" \
        background.height=20 \
	    background.color="$ITEM_BG_COLOR" \
        background.drawing=on \
        label="$sid" \
        label.color="$THM_PEACH"\
        click_script="aerospace workspace $sid" \
        script="$PLUGIN_DIR/aerospace.sh $sid" \
        icon.padding_right=0 \
        icon.padding_left=8 \
        label.padding_right=8 \
        label.padding_left=4 \
        background.padding_left=2\
        background.padding_right=2 
done
