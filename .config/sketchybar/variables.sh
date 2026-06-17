#!/usr/bin/env sh

# --- Catppuccin Mocha Palette ---
THM_ROSEWATER=0xfff5e0dc
THM_FLAMINGO=0xfff2cdcd
THM_PINK=0xfff5c2e7
THM_MAUVE=0xffcba6f7
THM_RED=0xfff38ba8
THM_MAROON=0xffeba0ac
THM_PEACH=0xfffab387
THM_YELLOW=0xfff9e2af
THM_GREEN=0xffa6e3a1
THM_TEAL=0xff94e2d5
THM_SKY=0xff89dceb
THM_SAPPHIRE=0xff74c7ec
THM_BLUE=0xff89b4fa
THM_LAVENDER=0xffb4befe
THM_TEXT=0xffcdd6f4
THM_SUBTEXT_1=0xffbac2de
THM_SUBTEXT_0=0xffa6adc8
THM_OVERLAY_2=0xff9399b2
THM_OVERLAY_1=0xff7f849c
THM_OVERLAY_0=0xff6c7086
THM_SURFACE_2=0xff585b70
THM_SURFACE_1=0xff45475a
THM_SURFACE_0=0xff313244
THM_BASE=0xff1e1e2e
THM_MANTLE=0xff181825
THM_CRUST=0xff11111b
# ------------------------------------
THM_TRANSPARENT=0x00000000

# needed directories - never change
ITEM_DIR="$HOME/.config/sketchybar/items"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

# best font
FONT="MesloLGS NF"

# bar options
BAR_BORDER_WIDTH=1
BAR_CORNER_RADIUS=8

# global item options
CORNER_RADIUS=4
BORDER_WIDTH=0

PADDINGS=3

RIGHT_ITEM_PADDING_RIGHT=0
LEFT_ITEM_PADDING_LEFT=1

SHADOW=on

# --- defaults that were referenced but never defined ---
ICON_COLOR="$THM_TEXT"          # per-item scripts override with an accent
LABEL_COLOR="$THM_SUBTEXT_1"    # neutral labels (the calm-the-rainbow move)
FONT_SIZE=12                    # used by plugins/events.sh

# --- floating island styling ---
# Translucent island fills (both 80% opacity, no blur). Point ISLAND_BG at one to switch.
ISLAND_BG_BLACK=0xcc000000      # pure black @ 80% — matches the WezTerm translucent background
ISLAND_BG="$THM_MANTLE"
ISLAND_RADIUS=7
ISLAND_HEIGHT=26
ISLAND_BORDER_COLOR="$THM_SURFACE_1"
ISLAND_BORDER_WIDTH=0           # bump to 1 to outline islands
ISLAND_SHADOW=on
ISLAND_SHADOW_COLOR=0x40000000
ISLAND_SHADOW_DISTANCE=3
ISLAND_SHADOW_ANGLE=90

# --- active workspace (soft raise) ---
ACCENT_ACTIVE="$THM_PEACH"      # focused workspace number color
WS_IDLE="$THM_OVERLAY_0"        # idle (non-empty) workspace number
WS_EMPTY="$THM_SURFACE_2"       # empty workspace number (dimmer than idle)
WS_CHIP="$THM_SURFACE_1"        # chip behind the focused number

# --- motion ---
ANIM_CURVE=tanh
ANIM_DURATION=18

# --- spacing between floating islands ---
ISLAND_GAP=8                   # px of empty air between adjacent islands
