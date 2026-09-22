local M = {}

M.git_icon = "󰘬"
M.branch_color = "\27[38;2;108;112;134m"
M.agent_color = "\27[38;2;166;227;161m"
M.busy_color = "\27[38;2;250;179;135m"
M.reset = "\27[0m"
M.tab = "\t"

M.home = os.getenv("HOME") or ""
M.state_root = os.getenv("XDG_STATE_HOME") or (M.home .. "/.local/state")
M.runtime_dir = os.getenv("XDG_RUNTIME_DIR") or os.getenv("TMPDIR") or "/tmp"

M.status_dir = M.state_root .. "/sesh-agents"
M.chats_dir = M.home .. "/.config/cursor/chats"
-- Add an adapter module name here when wiring another agent CLI.
M.agent_adapters = { "cursor" }

M.fire_pane_file = M.runtime_dir .. "/sesh-popup.fire-pane"
M.fire_mode_file = M.runtime_dir .. "/sesh-popup.fire-mode"
M.fire_kind_file = M.runtime_dir .. "/sesh-popup.fire-kind"
M.fire_pid_file = M.runtime_dir .. "/sesh-popup.fire-pid"
M.prompt_file = M.runtime_dir .. "/sesh-popup.prompt"
M.tmux_sock_file = M.runtime_dir .. "/sesh-popup.tmux-sock"
M.view_file = M.runtime_dir .. "/sesh-popup.view"

M.path_prefix = "/opt/homebrew/bin:/usr/local/bin:"
  .. M.home .. "/go/bin:"
  .. M.home .. "/.nix-profile/bin:"
  .. (os.getenv("PATH") or "/usr/bin")

return M
