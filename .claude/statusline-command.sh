#!/bin/bash
# Claude Code statusLine script
#
# Renders, in order:
#   1. Model display name, with reasoning effort level appended in
#      brackets when present (e.g. "Claude Opus 4[high]", no separator
#      between the model name and the bracketed effort level)
#   2. Context window usage (used percentage)
#   3. Repo name
#   4. Git branch (dirty marker appended when there are uncommitted changes)
#   5. Session lines added/removed
#   6. Output style
#
# Managed by the statusline-setup agent. Ask Claude to update the status
# line and it will re-invoke that agent to edit this file.

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# --- 1. Repo name --------------------------------------------------------
# Prefer workspace.repo.name (parsed from the origin remote); fall back to
# the cwd's basename when there's no repo or no origin remote configured.
repo=$(printf '%s' "$input" | jq -r '.workspace.repo.name // empty')
if [ -z "$repo" ] && [ -n "$cwd" ]; then
  repo=$(basename "$cwd")
fi
[ -z "$repo" ] && repo="unknown"

# --- 2. Git branch + dirty marker ---------------------------------------
# Branch isn't in the JSON, so it's computed with git, scoped to the
# session's cwd, skipping optional locks so we never contend with a
# concurrent git process. "Dirty" includes untracked files, matching what
# `git status --porcelain` reports.
branch=""
dirty=""
if [ -n "$cwd" ] && [ -d "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
fi
[ -z "$branch" ] && branch="no-git"

# --- 3. Model name --------------------------------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "unknown-model"')

# --- 4. Reasoning effort level ------------------------------------------
# Optional top-level field: only included when the active model supports
# reasoning effort levels. If it's absent, say so explicitly.
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
[ -z "$effort" ] && effort="n/a"

# --- 5. Context window usage --------------------------------------------
# used_percentage may be null early in a session (before the first API
# response), so fall back to "n/a" then too.
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  ctx=$(awk -v p="$used_pct" 'BEGIN { printf "%.0f%% used", p }')
else
  ctx="n/a"
fi

# --- 6. Session lines added/removed --------------------------------------
lines_added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // 0')

# --- 7. Output style ------------------------------------------------------
style=$(printf '%s' "$input" | jq -r '.output_style.name // "default"')

# --- Colors (soft/dim 256-color palette) ---------------------------------
C_REPO='\033[38;5;180m'    # soft tan
C_GIT='\033[38;5;183m'     # soft purple
C_DIRTY='\033[38;5;203m'   # soft red
C_MODEL='\033[38;5;110m'   # soft blue
C_EFFORT='\033[38;5;222m'  # soft yellow
C_CTX='\033[38;5;150m'     # soft green
C_ADD='\033[38;5;150m'     # soft green
C_DEL='\033[38;5;203m'     # soft red
C_STYLE='\033[38;5;175m'   # soft pink
C_DIM='\033[2;37m'         # dim separator
RESET='\033[0m'

branch_seg=$(printf "${C_GIT}%s${C_DIRTY}%s${RESET}" "$branch" "$dirty")
lines_seg=$(printf "${C_ADD}+%s${RESET}/${C_DEL}-%s${RESET}" "$lines_added" "$lines_removed")

printf "${C_MODEL}%s${RESET}${C_DIM}[${RESET}${C_EFFORT}%s${RESET}${C_DIM}]${RESET} ${C_DIM}·${RESET} ${C_CTX}Ctx:%s${RESET} ${C_DIM}·${RESET} ${C_REPO}%s${RESET} ${C_DIM}/${RESET} %s ${C_DIM}·${RESET} %s ${C_DIM}·${RESET} ${C_STYLE}Style:%s${RESET}\n" \
  "$model" "$effort" "$ctx" "$repo" "$branch_seg" "$lines_seg" "$style"
