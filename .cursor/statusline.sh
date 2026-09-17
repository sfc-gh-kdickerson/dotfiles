#!/usr/bin/env bash
# Cursor CLI status line
#
# Renders: model[+params] · ctx% · repo / branch* · [worktree] · [vim]
# Uses only fields from Cursor's StatusLinePayload.

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# --- Repo / directory name ----------------------------------------------
repo=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  repo=$(basename "$cwd")
fi
[ -z "$repo" ] && repo="unknown"

# --- Git branch + dirty marker ------------------------------------------
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

# --- Model + params -----------------------------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "unknown"')
params=$(printf '%s' "$input" | jq -r '.model.param_summary // empty')
max_mode=$(printf '%s' "$input" | jq -r '.model.max_mode // false')

# --- Context window -----------------------------------------------------
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
  ctx=$(awk -v p="$used_pct" 'BEGIN { printf "%.0f%%", p }')
else
  ctx="—"
fi

# --- Optional: worktree, vim --------------------------------------------
worktree=$(printf '%s' "$input" | jq -r '.worktree.name // empty')
vim_mode=$(printf '%s' "$input" | jq -r '.vim.mode // empty')

# --- Colors -------------------------------------------------------------
C_MODEL='\033[38;5;110m'
C_PARAMS='\033[38;5;222m'
C_CTX='\033[38;5;150m'
C_REPO='\033[38;5;180m'
C_GIT='\033[38;5;183m'
C_DIRTY='\033[38;5;203m'
C_WT='\033[38;5;116m'
C_VIM='\033[38;5;175m'
C_DIM='\033[2;37m'
RESET='\033[0m'

# Model segment (optional param_summary / max)
model_seg=$(printf "${C_MODEL}%s${RESET}" "$model")
if [ -n "$params" ]; then
  model_seg+=$(printf "${C_DIM} ${RESET}${C_PARAMS}%s${RESET}" "$params")
fi
if [ "$max_mode" = "true" ]; then
  model_seg+=$(printf "${C_DIM} ${RESET}${C_PARAMS}max${RESET}")
fi

# Build segments (vim mode leftmost when present)
parts=()
if [ -n "$vim_mode" ]; then
  parts+=("$(printf "${C_VIM}%s${RESET}" "$vim_mode")")
fi
parts+=("$model_seg")
parts+=("$(printf "${C_CTX}ctx %s${RESET}" "$ctx")")
parts+=("$(printf "${C_REPO}%s${RESET}" "$repo")")

if [ -n "$branch" ]; then
  parts+=("$(printf "${C_GIT}%s${C_DIRTY}%s${RESET}" "$branch" "$dirty")")
fi

if [ -n "$worktree" ]; then
  parts+=("$(printf "${C_WT}wt:%s${RESET}" "$worktree")")
fi

sep=$(printf " ${C_DIM}·${RESET} ")
out="${parts[0]}"
for ((i = 1; i < ${#parts[@]}; i++)); do
  out+="${sep}${parts[i]}"
done
printf '%b\n' "$out"
