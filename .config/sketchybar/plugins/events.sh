#!/usr/bin/env bash

text="$(python3 ~/dotfiles/.config/sketchybar/plugins/upcoming_events.py kaleb.dickerson@snowflake.com)"


if [ "$text" = "No Upcoming" ]; then
    sketchybar --set "$NAME" icon="󱁖" label="$text" label.font.size=$FONT_SIZE
else
    sketchybar --set "$NAME" icon="󰃶" label="$text" label.font.size=11
fi

