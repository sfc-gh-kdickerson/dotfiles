# Helper function to copy stdin to local clipboard via OSC 52
cbcopy() {
    local buffer
    buffer=$(base64 | tr -d '\r\n')
    if [ -n "$TMUX" ]; then
        # Wrap sequence for tmux escape tracking
        printf "\033Ptmux;\033\033]52;c;%s\007\033\\" "$buffer"
    else
        printf "\033]52;c;%s\007" "$buffer"
    fi
}

# Merge gate + precommit enforcer status for a PR (defaults to current branch).
# Watch mode: pr-gates -w [-i 30] [PR]
# hwatch also works: hwatch -i 30 -- zsh -ic 'pr-gates'
pr-gates() {
    emulate -L zsh
    setopt localoptions

    local watch=0 interval=30
    local -a pr_target=()

    while (( $# )); do
        case $1 in
            -w | --watch)
                watch=1
                shift
                ;;
            -i | --interval)
                interval=$2
                if [[ -z "$interval" || "$interval" != <-> ]]; then
                    print -u2 "pr-gates: --interval requires a positive integer (seconds)"
                    return 1
                fi
                shift 2
                ;;
            -h | --help)
                cat <<'EOF'
Usage: pr-gates [options] [PR]

Show merge gates, failing checks, and precommit enforcer status.

Options:
  -w, --watch           Refresh continuously (requires a TTY)
  -i, --interval SEC    Refresh interval in watch mode (default: 30)
  -h, --help            Show this help

Examples:
  pr-gates
  pr-gates 508951
  pr-gates -w
  pr-gates -w -i 15 508951
  hwatch -i 30 -- zsh -ic 'pr-gates'
EOF
                return 0
                ;;
            --)
                shift
                pr_target=("$@")
                break
                ;;
            -*)
                print -u2 "pr-gates: unknown option: $1"
                return 1
                ;;
            *)
                pr_target=("$@")
                break
                ;;
        esac
    done

    if (( watch )); then
        if [[ ! -t 1 ]]; then
            print -u2 "pr-gates: watch mode requires a TTY (try: pr-gates -w)"
            return 1
        fi
        while true; do
            clear
            _pr_gates_render "${pr_target[@]}"
            print
            _pr_gates_watch_footer "$interval"
            sleep "$interval" || return $?
        done
    fi

    _pr_gates_render "${pr_target[@]}"
}

_pr_gates_render() {
    emulate -L zsh
    setopt localoptions

    local -a pr_arg=("$@")
    local repo pr_json checks_json
    local number title url branch state is_draft merge reviews sha pr_status
    local use_color=1
    [[ -t 1 ]] || use_color=0

    typeset -r B=$'\033[1m'
    typeset -r FG_RED=$'\033[38;2;243;139;168m'
    typeset -r FG_GREEN=$'\033[38;2;166;227;161m'
    typeset -r FG_YELLOW=$'\033[38;2;249;226;175m'
    typeset -r FG_BLUE=$'\033[38;2;137;180;250m'
    typeset -r FG_CYAN=$'\033[38;2;148;226;213m'
    typeset -r FG_WHITE=$'\033[38;2;205;214;244m'
    typeset -r FG_MUTED=$'\033[38;2;166;173;200m'

    _tone() {
        local code=$1
        shift
        if (( use_color )); then
            print -rn -- "${code}${*}"
        else
            print -rn -- "$*"
        fi
    }

    _toneln() {
        _tone "$@"
        print
    }

    _kv() {
        local label=$1 tone=$2 value=$3 width=${4:-12}
        printf '  %-'"${width}"'s ' "$label"
        _toneln "$tone" "$value"
    }

    _status_kv() {
        local label=$1 value=$2 tone=$FG_CYAN
        case "$value" in
            CLEAN|APPROVED|OPEN|MERGED|SUCCESS|pass) tone=$FG_GREEN ;;
            DRAFT|BEHIND|REVIEW_REQUIRED|pending) tone=$FG_YELLOW ;;
            UNSTABLE|BLOCKED|FAILURE|fail|CHANGES_REQUESTED|CLOSED) tone=$FG_RED ;;
            ''|'—'|—) tone=$FG_MUTED ;;
        esac
        _kv "$label" "$tone" "$value"
    }

    _pr_status_tone() {
        case "$1" in
            DRAFT) _tone "$FG_YELLOW" "$1" ;;
            OPEN|MERGED) _tone "$FG_GREEN" "$1" ;;
            CLOSED) _tone "$FG_RED" "$1" ;;
            *) _tone "$FG_CYAN" "$1" ;;
        esac
    }

    pr_json=$(gh pr view "${pr_arg[@]}" --json number,title,url,headRefName,state,isDraft,mergeStateStatus,reviewDecision,headRefOid) || return $?
    checks_json=$(gh pr checks "${pr_arg[@]}" --json name,state,bucket,link 2>/dev/null) || checks_json='[]'
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || return $?

    number=$(jq -r .number <<<"$pr_json")
    title=$(jq -r .title <<<"$pr_json")
    url=$(jq -r .url <<<"$pr_json")
    branch=$(jq -r .headRefName <<<"$pr_json")
    state=$(jq -r .state <<<"$pr_json")
    is_draft=$(jq -r .isDraft <<<"$pr_json")
    merge=$(jq -r .mergeStateStatus <<<"$pr_json")
    reviews=$(jq -r .reviewDecision <<<"$pr_json")
    sha=$(jq -r .headRefOid <<<"$pr_json")

    pr_status=$state
    if [[ "$state" == OPEN && "$is_draft" == true ]]; then
        pr_status=DRAFT
    fi
    [[ -z "$reviews" || "$reviews" == null ]] && reviews='—'

    print
    _tone "$FG_BLUE" "PR "
    _tone "$FG_CYAN" "#${number}"
    _tone "$FG_MUTED" " · "
    _pr_status_tone "$pr_status"
    print
    _toneln "$FG_WHITE$B" "$title"
    _tone "$FG_CYAN" "$branch"
    _tone "$FG_MUTED" " · "
    _toneln "$FG_WHITE" "$repo"
    _toneln "$FG_BLUE" "$url"
    print

    _status_kv "PR status" "$pr_status"
    _status_kv "Merge" "$merge"
    _status_kv "Reviews" "$reviews"
    print

    local -a failing=()
    local has_buildkite_check=0
    if jq -e '.[] | select(.name | startswith("Buildkite - "))' <<<"$checks_json" >/dev/null 2>&1; then
        has_buildkite_check=1
    fi

    while IFS=$'\t' read -r bucket name link; do
        [[ -z "$name" ]] && continue
        if (( has_buildkite_check )) && [[ "$name" == buildkite/* ]]; then
            continue
        fi
        failing+=("$bucket|$name|$link")
    done < <(jq -r '.[] | select(.bucket != "pass") | [.bucket, .name, .link] | @tsv' <<<"$checks_json")

    if (( ${#failing[@]} )); then
        _toneln "$FG_YELLOW$B" "Checks (${#failing[@]} failing)"
        local entry bucket name link mark tone
        for entry in "${failing[@]}"; do
            bucket="${entry%%|*}"
            name="${entry#*|}"
            name="${name%%|*}"
            link="${entry##*|}"
            mark='✗' tone=$FG_RED
            if [[ "$bucket" == pending ]]; then
                mark='…' tone=$FG_YELLOW
            fi
            printf '  '
            _tone "$tone" "$mark "
            _tone "$FG_WHITE" "$name"
            if [[ -n "$link" && "$link" != null ]]; then
                _tone "$FG_MUTED" "  "
                _toneln "$FG_BLUE" "$link"
            else
                print
            fi
        done
    else
        _tone "$FG_GREEN" "Checks"
        _toneln "$FG_WHITE" "  all passing"
    fi
    print

    _toneln "$FG_YELLOW$B" "Precommit enforcer"
    local precommit_summary filtered
    precommit_summary=$(
        gh api "repos/${repo}/commits/${sha}/check-runs" \
            --jq '.check_runs[] | select(.name=="SnowCI: Precommit-Enforcer (New)") | .output.summary' 2>/dev/null
    )

    _precommit_tone() {
        local label=$1 value=$2
        case "$label" in
            Reason|Message) _tone "$FG_WHITE" "$value" ;;
            'Has NO_PRECOMMIT_RUN'|'Precommit build state')
                case "$value" in
                    N/A|false) _tone "$FG_GREEN" "$value" ;;
                    *) _tone "$FG_RED" "$value" ;;
                esac ;;
            'Precommit build commit')
                case "$value" in
                    N/A) _tone "$FG_YELLOW" "$value" ;;
                    *) _tone "$FG_GREEN" "$value" ;;
                esac ;;
            *) _tone "$FG_CYAN" "$value" ;;
        esac
    }

    if (( ${#precommit_summary} == 0 )); then
        _kv "Status" "$FG_MUTED" "(no Precommit-Enforcer check found)"
    else
        filtered=$(command rg '^(Reason|Message|Precommit build state|Precommit build commit|Has NO_PRECOMMIT_RUN):' <<<"${precommit_summary//\`/}") || return 0
        local line label value
        while IFS= read -r line; do
            label="${line%%:*}"
            value="${line#*: }"
            value="${value#"${value%%[![:space:]]*}"}"
            printf '  %-22s ' "$label"
            _precommit_tone "$label" "$value"
            print
        done <<< "$filtered"
    fi
}

_pr_gates_watch_footer() {
    local interval=$1
    local ts
    ts=$(date '+%H:%M:%S')
    if [[ -t 1 ]]; then
        print -Pn "%F{8}  refreshed ${ts} · every ${interval}s · Ctrl+C to quit%f"
    else
        print "  refreshed ${ts} · every ${interval}s · Ctrl+C to quit"
    fi
}
