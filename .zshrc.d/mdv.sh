# md - view a markdown file on a Solarized-Light-colored background, applied to
# the current tmux pane only. Falls back to plain rendering when not inside tmux.
#
# -i <impl>   Renderer implementation to use: "mdv" (default) or "mdfried".
#
# Restoring via `select-pane -P default` sets the pane-scoped options window-style
# AND window-active-style to the literal string "default" - still an explicit
# per-pane override that permanently shadows window-active-style dimming/tinting
# (e.g. bg=#{@thm_mantle} in .tmux.conf) instead of falling back to it. The real
# unset is `set-option -pu`, which removes the pane-scoped override entirely so the
# pane re-inherits window-level window-style/window-active-style dynamically again.
md() {
    local impl="mdv"

    while [[ "$1" == -* ]]; do
        case "$1" in
            -i)
                impl="$2"
                shift 2
                ;;
            *)
                echo "md: unknown flag $1" >&2
                return 1
                ;;
        esac
    done

    local -a cmd
    case "$impl" in
        mdv)
            cmd=(mdv -p)
            ;;
        mdfried)
            cmd=(mdfried)
            ;;
        *)
            echo "md: unsupported implementation '$impl' (expected 'mdv' or 'mdfried')" >&2
            return 1
            ;;
    esac

    if [[ -z "$TMUX" ]]; then
        echo "md: not inside tmux, skipping background override" >&2
        "${cmd[@]}" "$@"
        return
    fi

    local pane_id
    pane_id="$(tmux display-message -p '#{pane_id}')"

    trap "tmux set-option -pu -t '$pane_id' window-style 2>/dev/null; tmux set-option -pu -t '$pane_id' window-active-style 2>/dev/null; trap - INT" INT

    tmux select-pane -t "$pane_id" -P 'bg=#fdf6e3,fg=#073642'
    "${cmd[@]}" "$@"

    tmux set-option -pu -t "$pane_id" window-style 2>/dev/null
    tmux set-option -pu -t "$pane_id" window-active-style 2>/dev/null
    trap - INT
}
