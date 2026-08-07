# mdvl - view a markdown file with mdv's interactive pager on a Solarized-Light-colored
# background, applied to the current tmux pane only. Falls back to plain `mdv -p`
# when not inside tmux.
#
# Restoring via `select-pane -P default` sets the pane-scoped options window-style
# AND window-active-style to the literal string "default" - still an explicit
# per-pane override that permanently shadows window-active-style dimming/tinting
# (e.g. bg=#{@thm_mantle} in .tmux.conf) instead of falling back to it. The real
# unset is `set-option -pu`, which removes the pane-scoped override entirely so the
# pane re-inherits window-level window-style/window-active-style dynamically again.
mdvl() {
    if [[ -z "$TMUX" ]]; then
        echo "mdvl: not inside tmux, skipping background override" >&2
        mdv -p "$@"
        return
    fi

    local pane_id
    pane_id="$(tmux display-message -p '#{pane_id}')"

    trap "tmux set-option -pu -t '$pane_id' window-style 2>/dev/null; tmux set-option -pu -t '$pane_id' window-active-style 2>/dev/null; trap - INT" INT

    tmux select-pane -t "$pane_id" -P 'bg=#fdf6e3,fg=#073642'
    mdv -p "$@"

    tmux set-option -pu -t "$pane_id" window-style 2>/dev/null
    tmux set-option -pu -t "$pane_id" window-active-style 2>/dev/null
    trap - INT
}
