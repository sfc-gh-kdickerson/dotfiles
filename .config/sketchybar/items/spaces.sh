#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change

COLOR="$THM_PEACH"

for sid in $(aerospace list-workspaces --all); do
    sketchybar --add item space.$sid left \
        --subscribe space.$sid aerospace_workspace_change \
        --set space.$sid \
        label="$sid" \
        background.color="$COMMENT" \
        background.corner_radius="$CORNER_RADIUS" \
        background.height=20 \
        background.color="$THM_SURFACE_1" \
        background.drawing=off \
        background.border_width="$BORDER_WIDTH" \
        label.color="$THM_TEXT"\
        click_script="aerospace workspace $sid" \
        script="$PLUGIN_DIR/aerospace.sh $sid" \
        label.padding_right=8 \
        label.padding_left=1 \
        background.padding_left=0\
        background.padding_right=0
done
