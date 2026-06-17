#!/usr/bin/env bash

source ~/dotfiles/.config/sketchybar/variables.sh

sid="$1"
focused="$AEROSPACE_FOCUSED_WORKSPACE"
[ -z "$focused" ] && focused="$(aerospace list-workspaces --focused 2>/dev/null)"

# Is this workspace non-empty (has windows) on any monitor?
nonempty=off
while IFS= read -r ws; do
    [ "$ws" = "$sid" ] && nonempty=on && break
done <<< "$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)"

if [ "$sid" = "$focused" ]; then
    sketchybar --animate "$ANIM_CURVE" "$ANIM_DURATION" --set "$NAME" \
        drawing=on \
        background.drawing=on \
        background.color="$WS_CHIP" \
        label.color="$ACCENT_ACTIVE"
elif [ "$nonempty" = "on" ]; then
    sketchybar --animate "$ANIM_CURVE" "$ANIM_DURATION" --set "$NAME" \
        drawing=on \
        background.drawing=off \
        label.color="$WS_IDLE"
else
    sketchybar --animate "$ANIM_CURVE" "$ANIM_DURATION" --set "$NAME" \
        drawing=on \
        background.drawing=off \
        label.color="$WS_EMPTY"
fi
