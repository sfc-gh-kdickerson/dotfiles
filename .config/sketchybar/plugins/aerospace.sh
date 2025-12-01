#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

ACTIVE_COLOR=$THM_GREEN
INACTIVE_COLOR=$THM_PEACH
INACTIVE_COLOR=$THM_MAROON


if [ "$1" = "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME label.color=$ACTIVE_COLOR icon="" icon.color=$ACTIVE_COLOR background.border_color=$ACTIVE_COLOR
else
    sketchybar --set $NAME label.color=$INACTIVE_COLOR icon="" icon.color=$INACTIVE_COLOR background.border_color=$INACTIVE_COLOR
fi
