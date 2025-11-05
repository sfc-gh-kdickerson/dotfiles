#!/bin/sh

# git worktree switch
function gwts() {
  local branch_name="$1"
  local target_worktree=""
  local worktree_list=""

  # 1. Ensure we are inside a Git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a Git repository or worktree. Aborting."
    return 1
  fi

  # Get the full list of worktrees (Path, Commit, Branch)
  worktree_list=$(git worktree list)

  if [[ -n "$branch_name" ]]; then
    # 2. Check if a worktree exists for the given branch name
    # We use 'grep' to find the line containing the branch name, 
    # then 'awk' to extract the path (the first column).
    # We use \b to ensure it's a whole word match for the branch name.
    target_worktree=$(echo "$worktree_list" | grep -E "\b${branch_name}\b" | awk '{print $1}')
    
    if [[ -z "$target_worktree" ]]; then
      echo "Branch '$branch_name' is not currently checked out in a worktree."
      echo "Continuing to interactive selection..."
    fi
  fi

  # 3. Fallback to fzf if no branch name was provided or no matching worktree was found
  if [[ -z "$target_worktree" ]]; then
    # Use fzf on the full list for selection
    local selected_line
    selected_line=$(echo "$worktree_list" | fzf)

    if [[ -z "$selected_line" ]]; then
      echo "No worktree selected. Aborting."
      return 1
    fi
    
    # Extract the path from the selected line (always the first column)
    target_worktree=$(echo "$selected_line" | awk '{print $1}')
    
    # Optional: Extract branch name for the success message
    branch_name=$(echo "$selected_line" | awk '{print $NF}' | tr -d '[]()')
  fi

  # 4. Change the directory of the current shell
  # We use the built-in 'cd' command to ensure the shell's directory is changed.
  cd "$target_worktree" && clear
}

# git worktree create branch, new tmux window, and cd into it
function gwtcb() {
  if [ -z "$1" ]; then
    echo "Usage: gwtcb <new-branch-name>"
    return 1
  fi

  local branch_name="$1"
  local worktree_path="../${branch_name}" # Adjust this path as needed
  
  # 1. Create the worktree and new branch
  echo "Creating new worktree at ${worktree_path} and branch ${branch_name}..."
  if ! git worktree add -b "${branch_name}" "${worktree_path}"; then
    echo "Error creating git worktree and branch. Aborting."
    return 1
  fi
  
  # 2. Create a new tmux window and change directory
  if command -v tmux &> /dev/null; then
    echo "Creating new tmux window '${branch_name}' and navigating to worktree..."
    # 'new-window' creates a new window
    # '-n' sets the window name
    # '-c' sets the starting directory for the new window
    tmux new-window -n "${branch_name}" -c "${worktree_path}"
  else
    echo "tmux is not installed or not in PATH. Worktree created, but no new window opened."
    echo "Worktree location: ${worktree_path}"
  fi
}
