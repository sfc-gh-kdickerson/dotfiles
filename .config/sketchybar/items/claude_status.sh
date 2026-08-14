#!/usr/bin/env bash

# Gap before this island (sits between ai_spend_island and claude_status_island) —
# every other item cluster in this bar adds its own explicit-width spacer for this
# (see ai_spend.sh's spc.ai_spend, volume.sh's spc.time); this one was missing it.
sketchybar --add item spc.claude_status left \
	--set spc.claude_status icon.drawing=off label.drawing=off background.drawing=off width=10

# The icon glyph was silently coming out as an empty string (verified via a hex
# dump of this file — `icon=$''` had zero bytes between the quotes), which is what
# looked like "too much left padding": no missing font glyph, just no glyph at all.
# Using bash's \uXXXX escape (nf-fa-terminal, U+F120) instead of a literal
# character sidesteps whatever was dropping the literal glyph on write.
# Tighter padding than the usual icon.padding_left=10 convention — this item's
# label is often short ("9 idle"), and the standard inset looked disproportionate
# against a short label.
sketchybar --add item claude_status left \
	--set claude_status \
	update_freq=10 \
	icon=$'' \
	icon.color="$THM_OVERLAY_0" \
	icon.padding_left=6 \
	icon.padding_right=4 \
	label.color="$LABEL_COLOR" \
	label.padding_right=6 \
	label.drawing=off \
	background.drawing=off \
	popup.background.color="$ISLAND_BG" \
	popup.background.corner_radius="$ISLAND_RADIUS" \
	popup.background.border_width=1 \
	popup.background.border_color="$ISLAND_BORDER_COLOR" \
	popup.y_offset=5 \
	script="$PLUGIN_DIR/claude_status.sh" \
	click_script="sketchybar --set claude_status popup.drawing=toggle"
