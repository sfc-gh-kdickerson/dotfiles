#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

text="$(python3 ~/dotfiles/.config/sketchybar/plugins/upcoming_events.py kaleb.dickerson@snowflake.com)"


if [ "$text" = "No Upcoming" ]; then
    sketchybar --set "$NAME" icon="󱁖" label="$text" label.font.size=$FONT_SIZE
else
    sketchybar --set "$NAME" icon="󰃶" label="$text" label.font.size=$FONT_SIZE
fi

