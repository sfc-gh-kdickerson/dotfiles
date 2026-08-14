#!/usr/bin/env bash
# Jumps to a specific tmux session/window/pane and brings the terminal forward.
# Invoked from claude_status.sh's popup rows with the target baked in as args.
#
# Known v1 limitations (accepted, not bugs):
#   - if multiple tmux clients are attached, only the first one found is retargeted
#   - if multiple Ghostty windows are open, `open -a Ghostty` may not raise the
#     exact one now showing the target session
set -uo pipefail

SESSION="$1"
WINDOW="$2"
PANE="$3"
TARGET="${SESSION}:${WINDOW}.${PANE}"

GHOSTTY_APP="/Applications/Ghostty.app"

CLIENT_TTY="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n1)"

if [ -n "$CLIENT_TTY" ]; then
	# switch-client's -t special-cases a compound target (contains ':' or '.') to
	# change session, window, AND pane in one call — no follow-up
	# select-window/select-pane needed (confirmed against tmux's own manpage text).
	tmux switch-client -c "$CLIENT_TTY" -t "$TARGET"
else
	# No attached client to retarget — spawn a new Ghostty window attached to the
	# session. `ghostty -e ...` does not work on macOS (Ghostty's own --help says
	# CLI-launching the terminal emulator is unsupported there); must go through
	# `open -na`.
	open -na "$GHOSTTY_APP" --args -e "tmux attach -t $(printf '%q' "$SESSION")"
fi

# Best-effort bring Ghostty to front.
open -a Ghostty
