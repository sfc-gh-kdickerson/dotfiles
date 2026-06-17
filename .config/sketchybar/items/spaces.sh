#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change

for sid in $(aerospace list-workspaces --all); do
    sketchybar --add item space.$sid left \
        --subscribe space.$sid aerospace_workspace_change front_app_switched \
        --set space.$sid \
        label="$sid" \
        label.color="$WS_IDLE" \
        label.padding_left=6 \
        label.padding_right=6 \
        icon.drawing=off \
        background.drawing=off \
        background.color="$WS_CHIP" \
        background.corner_radius=4 \
        background.height=20 \
        click_script="aerospace workspace $sid" \
        script="$PLUGIN_DIR/aerospace.sh $sid"
done

# paint correct initial state (focused / non-empty / empty) for every workspace
sketchybar --trigger aerospace_workspace_change
