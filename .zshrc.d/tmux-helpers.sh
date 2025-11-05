# Function to rename the current tmux window to the current Git branch
function rename_window_to_git_branch() {
  # Check if we are inside a tmux session and a git repository
  if [[ -n "$TMUX" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Get the current branch name, suppressing errors if not on a branch
    local branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    # Use 'tmux rename-window' to set the window name
    if [[ -n "$branch_name" ]]; then
      tmux rename-window "$branch_name"
    else
      # Fallback name if not on a branch (e.g., detached HEAD)
      tmux rename-window "detached-HEAD"
    fi
  elif [[ -n "$TMUX" ]]; then
    # Optional: rename to current directory if not in a git repo
    tmux rename-window "$(basename "$PWD")"
  fi
}
