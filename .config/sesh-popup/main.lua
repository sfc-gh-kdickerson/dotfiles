#!/usr/bin/env luajit
-- sesh-popup — tmux session/agent picker (fzf-tmux UI, Lua core).
-- Agent backends live in agents/*.lua; only cursor is wired today.

local util = require("util")
local config = require("config")
local list = require("list")
local sesh = require("sesh")
local tmux = require("tmux")
local fire = require("fire")
local picker = require("picker")
local connect = require("connect")
local registry = require("agents.registry")

local self_cmd = os.getenv("SESH_POPUP_CMD")
  or ((os.getenv("HOME") or "") .. "/scripts/sesh-popup")

local cmd = arg[1]

if cmd == "list" then
  local sub = arg[2]
  if sub == "panes" then
    list.panes()
  elseif sub == "agents" then
    list.agents(arg[3] == "ready")
  else
    local args = {}
    for i = 2, #arg do
      args[#args + 1] = arg[i]
    end
    sesh.list_sessions(table.concat(args, " "))
  end
  os.exit(0)
end

if cmd == "kill" then
  tmux.kill(arg[2] or "", arg[3] or "")
  os.exit(0)
end

if cmd == "relist" then
  list.relist(arg[2] or "")
  os.exit(0)
end

if cmd == "current" then
  local view = "sessions"
  local view_file = arg[2]
  if view_file then
    local data = util.read_file(view_file)
    if data then
      view = data:gsub("\n$", "")
    end
  end
  list.current(view)
  os.exit(0)
end

if cmd == "preview" then
  if arg[2] == "agent" then
    local pane = arg[3]
    local adapter = registry.for_pane(pane)
    if adapter then
      io.write(adapter.preview(pane, os.getenv("FZF_PREVIEW_COLUMNS") or "56"))
    end
  elseif arg[2] == "session" then
    list.preview_session(arg[3], arg[4])
  elseif arg[2] == "pane" then
    list.preview_pane(arg[3])
  end
  os.exit(0)
end

if cmd == "fzf-ctrl-s" then
  fire.ctrl_s(arg[2] or "", arg[3] or "")
  os.exit(0)
end

if cmd == "fzf-enter" then
  local kind = arg[2] or ""
  local pane = arg[3] or ""
  local msg = table.concat(arg, " ", 4)
  fire.enter(kind, pane, msg)
  os.exit(0)
end

if cmd == "fzf-esc" then
  fire.esc()
  os.exit(0)
end

if cmd == "fzf-ready" then
  local view = util.read_file(config.view_file) or ""
  view = view:gsub("\n$", "")
  fire.clear_state()
  if view == "agents" then
    util.write_file(config.view_file, "agents-ready\n")
    io.write(
      "change-prompt(󰚩  )+change-preview-window(up,55%)+reload("
        .. util.shell_quote(self_cmd)
        .. " list agents ready)+change-header("
        .. picker.legend(true)
        .. ")\n"
    )
  elseif view == "agents-ready" then
    util.write_file(config.view_file, "agents\n")
    io.write(
      "change-prompt(󰚩  )+change-preview-window(up,55%)+reload("
        .. util.shell_quote(self_cmd)
        .. " list agents)+change-header("
        .. picker.legend(true)
        .. ")\n"
    )
  else
    io.write("ignore\n")
  end
  os.exit(0)
end

-- Default: open picker
util.need("sesh")
util.need("fzf-tmux")

local initial = cmd == "agents"
local selected

if initial then
  selected = picker.run({
    self_cmd = self_cmd,
    prompt = "󰚩  ",
    size = "70%,80%",
    preview_window = "up,55%",
    view = "agents",
    agent_view = true,
    list_cmd = string.format(
      "PATH=%s %s list agents",
      util.shell_quote(config.path_prefix),
      util.shell_quote(self_cmd)
    ),
  })
else
  selected = picker.run({
    self_cmd = self_cmd,
    prompt = "  ",
    size = "70%,80%",
    preview_window = "up,55%",
    view = "sessions",
    list_cmd = string.format(
      "PATH=%s %s list -t -H",
      util.shell_quote(config.path_prefix),
      util.shell_quote(self_cmd)
    ),
  })
end

if selected and selected ~= "" then
  connect.fzf_output(selected)
end
