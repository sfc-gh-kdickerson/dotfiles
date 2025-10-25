#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

if [ "$1" = "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME label.color=$THM_GREEN icon="" icon.color=$THM_GREEN
else
    sketchybar --set $NAME label.color=$THM_PEACH icon="" icon.color=$THM_PEACH
fi
