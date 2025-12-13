#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

if [ "$1" = "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.drawing=on
else
    sketchybar --set $NAME background.drawing=off
fi
