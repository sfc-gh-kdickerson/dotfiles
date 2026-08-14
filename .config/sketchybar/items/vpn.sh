#!/usr/bin/env bash

# gap before this island (sits between vpn and sysisland)
sketchybar --add item spc.sys right \
    --set spc.sys icon.drawing=off label.drawing=off background.drawing=off

sketchybar --add alias "Control Center,com.paloaltonetworks.GlobalProtect.client" right \
    --set "Control Center,com.paloaltonetworks.GlobalProtect.client" \
    alias.update_freq=60 \
    alias.color="$THM_PEACH" \
    alias.scale=0.8 \
    background.drawing=on \
    background.color="$ISLAND_BG" \
    background.corner_radius="$ISLAND_RADIUS" \
    background.height="$ISLAND_HEIGHT" \
    background.border_width="$ISLAND_BORDER_WIDTH" \
    background.border_color="$ISLAND_BORDER_COLOR" \
    background.shadow.drawing="$ISLAND_SHADOW" \
    background.shadow.color="$ISLAND_SHADOW_COLOR" \
    background.shadow.distance="$ISLAND_SHADOW_DISTANCE" \
    background.shadow.angle="$ISLAND_SHADOW_ANGLE"
