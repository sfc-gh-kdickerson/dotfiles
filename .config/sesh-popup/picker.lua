local config = require("config")
local util = require("util")
local tmux = require("tmux")
local fire = require("fire")

local M = {}

function M.legend(agent_view)
  local legend = "  "
    .. config.branch_color
    .. "C-a all  C-t tmux  C-x zoxide  C-p panes  C-e agents  C-s fire  C-d kill"
    .. config.reset
  if agent_view then
    legend = legend .. "  " .. config.branch_color .. "C-r ready" .. config.reset
  end
  return legend
end

function M.header(extra)
  if extra and extra ~= "" then
    return "  " .. extra .. "  " .. M.legend():gsub("^  ", "")
  end
  return M.legend()
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.run(opts)
  util.write_file(config.view_file, opts.view .. "\n")
  util.write_file(config.prompt_file, opts.prompt .. "\n")
  tmux.save_sock()
  fire.clear_state()

  local self_cmd = opts.self_cmd
  local self_q = shell_quote(self_cmd)
  local fire_mode_q = shell_quote(config.fire_mode_file)
  local fire_pane_q = shell_quote(config.fire_pane_file)
  local fire_kind_q = shell_quote(config.fire_kind_file)
  local fire_pid_q = shell_quote(config.fire_pid_file)
  local prompt_q = shell_quote(config.prompt_file)
  local view_q = shell_quote(config.view_file)
  local legend = M.legend(opts.agent_view)
  local agent_legend = M.legend(true)
  local header = shell_quote(legend)
  local list_cmd = opts.list_cmd
  local preview_win = opts.preview_window
  local size = opts.size
  local prompt = opts.prompt

  -- Field 3 is the name, field 5 is the git branch; both are searchable.
  -- --tiebreak=begin keeps "main" (the session) above sessions that are
  -- merely on the main branch. Empty query still follows list order (index).
  local fzf = string.format(
    [[PATH=%s fzf-tmux -p %s \
      --ansi \
      --print-query \
      --delimiter='\t' --with-nth=3,5 --tabstop=1 --tiebreak=begin,index \
      --border-label ' sesh ' --prompt %s \
      --header %s \
      --preview %s \
      --preview-window %s \
      --bind 'tab:down,btab:up' \
      --bind %s \
      --bind 'start:execute-silent(stty -ixon < /dev/tty 2>/dev/null || true)' \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s \
      --bind %s]],
    shell_quote(config.path_prefix),
    shell_quote(size),
    shell_quote(prompt),
    header,
    shell_quote(self_q .. " preview {1} {2} {4}"),
    shell_quote(preview_win),
    shell_quote("enter:transform:" .. self_q .. " fzf-enter {1} {2} {q}"),
    shell_quote("esc:transform:" .. self_q .. " fzf-esc"),
    shell_quote("ctrl-a:execute-silent(rm -f "
      .. fire_mode_q .. " " .. fire_pane_q .. " " .. fire_kind_q .. " " .. fire_pid_q
      .. "; printf '%s\\n' '⚡  ' > " .. prompt_q
      .. "; printf '%s\\n' 'all' > " .. view_q
      .. ")+enable-search+change-prompt(⚡  )+change-preview-window(up,55%)+reload("
      .. self_q .. " list)+change-header(" .. legend .. ")"),
    shell_quote("ctrl-t:execute-silent(rm -f "
      .. fire_mode_q .. " " .. fire_pane_q .. " " .. fire_kind_q .. " " .. fire_pid_q
      .. "; printf '%s\\n' '  ' > " .. prompt_q
      .. "; printf '%s\\n' 'sessions' > " .. view_q
      .. ")+enable-search+change-prompt(  )+change-preview-window(up,55%)+reload("
      .. self_q .. " list -t -H)+change-header(" .. legend .. ")"),
    shell_quote("ctrl-x:execute-silent(rm -f "
      .. fire_mode_q .. " " .. fire_pane_q .. " " .. fire_kind_q .. " " .. fire_pid_q
      .. "; printf '%s\\n' '📁  ' > " .. prompt_q
      .. "; printf '%s\\n' 'zoxide' > " .. view_q
      .. ")+enable-search+change-prompt(📁  )+change-preview-window(up,55%)+reload("
      .. self_q .. " list -z)+change-header(" .. legend .. ")"),
    shell_quote("ctrl-p:execute-silent(rm -f "
      .. fire_mode_q .. " " .. fire_pane_q .. " " .. fire_kind_q .. " " .. fire_pid_q
      .. "; printf '%s\\n' '  ' > " .. prompt_q
      .. "; printf '%s\\n' 'panes' > " .. view_q
      .. ")+enable-search+change-prompt(  )+change-preview-window(up,55%)+reload("
      .. self_q .. " list panes)+change-header(" .. legend .. ")"),
    shell_quote("ctrl-e:execute-silent(rm -f "
      .. fire_mode_q .. " " .. fire_pane_q .. " " .. fire_kind_q .. " " .. fire_pid_q
      .. "; printf '%s\\n' '󰚩  ' > " .. prompt_q
      .. "; printf '%s\\n' 'agents' > " .. view_q
      .. ")+enable-search+change-prompt(󰚩  )+change-preview-window(up,55%)+reload("
      .. self_q .. " list agents)+change-header(" .. agent_legend .. ")"),
    shell_quote("ctrl-r:transform:" .. self_q .. " fzf-ready"),
    shell_quote("ctrl-s:transform:" .. self_q .. " fzf-ctrl-s {1} {2}"),
    shell_quote("ctrl-d:execute-silent(" .. self_q .. " kill {1} {2})+reload("
      .. self_q .. " current " .. view_q .. ")")
  )

  local cmd = string.format('%s | %s', list_cmd, fzf)
  local h = io.popen(cmd)
  if not h then
    return nil
  end
  local out = h:read("*a")
  local ok, reason, code = h:close()
  if not ok and code ~= 1 and code ~= 130 then
    error("fzf exited " .. tostring(code or reason or "unknown status"))
  end
  return out
end

return M
