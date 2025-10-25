#!/bin/sh
# git worktree switch
function gwts() {
  # Check if we are inside a tmux session
  if [[ -n "$TMUX" ]]; then
    local target_worktree=$(git worktree list | awk '{print $1}' | fzf)

    if [[ -z "$target_worktree" ]]; then
      echo "No worktree selected. Aborting."
      return 1
    fi

    local git_toplevel=$(git rev-parse --show-toplevel)
    local current_window=$(tmux list-windows -F "#{window_id} #{window_active}" | awk '$2=="1" {print $1}')

    tmux list-panes -t "$current_window" -F "#{pane_id}" | while read -r pane_id; do
      # Get the current path of the pane
      local pane_path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')

      # Calculate the relative path from the git root
      local relative_path=${pane_path##$git_toplevel}

      # If the pane is inside the git repository, construct the new path
      if [[ "$pane_path" == "$git_toplevel"* ]]; then
        local new_path="${target_worktree}${relative_path}"
        # Send the cd command to each pane
        tmux send-keys -t "$pane_id" "cd $new_path && clear" C-m
      else
        echo "Pane $pane_id is not in a git worktree. Skipping."
      fi
    done
  else
    echo "This command only works inside a tmux session."
  fi
}

function gcwt() {
  # Check if we are in a git repository at all
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not in a git repository. Exiting."
    return 1
  fi

  # Check if the current directory is the repository root
  local git_root=$(git rev-parse --show-toplevel)
  local current_dir=$(pwd)

  if [ "$git_root" != "$current_dir" ]; then
    echo "Error: Not in the root directory of the git repository. Exiting."
    return 1
  fi

  # Use fzf to let the user select a branch
  local branch_name=$(git branch --all | grep -v 'HEAD' | sed 's/  *//' | fzf --prompt="Select a branch to create a new worktree from: ")

  # Validate that the input is not empty
  if [ -z "$branch_name" ]; then
    echo "No branch selected. Exiting."
    return 1
  fi

  # Define the full path for the new worktree one level up
  local new_worktree_path="../${branch_name}"

  # Check if a directory with the same name already exists
  if [ -d "${new_worktree_path}" ]; then
    echo "Error: A directory named '${new_worktree_path}' already exists. Exiting."
    return 1
  fi

  # Create the new worktree and branch
  echo "Creating new worktree in '${new_worktree_path}' for branch '$branch_name'..."
  git worktree add "${new_worktree_path}" "$branch_name"

  # Check if the command was successful and provide feedback
  if [ $? -eq 0 ]; then
    echo "Successfully created worktree in '${new_worktree_path}' with branch '$branch_name'."
  else
    echo "Failed to create worktree."
    return 1
  fi
}
