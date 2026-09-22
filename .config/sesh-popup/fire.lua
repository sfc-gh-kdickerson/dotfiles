local config = require("config")
local util = require("util")
local registry = require("agents.registry")

local M = {}

local function header(extra)
  local legend = "  "
    .. config.branch_color
    .. "C-a all  C-t tmux  C-x zoxide  C-p panes  C-e agents  C-s fire  C-d kill"
    .. config.reset
  if extra and extra ~= "" then
    return "  " .. extra .. "  " .. legend:gsub("^  ", "")
  end
  return legend
end

function M.ctrl_s(kind, pane)
  if kind ~= "agent" or not pane or pane == "" then
    return
  end
  local adapter = registry.for_pane(pane)
  if not adapter then
    return
  end
  local state = adapter.read_state and adapter.read_state(pane)
  if not state or not state.pid then
    return
  end
  util.write_file(config.fire_pane_file, util.pane_num(pane) .. "\n")
  util.write_file(config.fire_kind_file, adapter.id .. "\n")
  util.write_file(config.fire_pid_file, tostring(state.pid) .. "\n")
  util.write_file(config.fire_mode_file, "")
  io.write(
    string.format(
      'change-prompt(fire> )+clear-query+change-header(%s)\n',
      "  type a message   enter send   esc cancel"
    )
  )
end

function M.enter(kind, pane, msg)
  if not util.file_exists(config.fire_mode_file) then
    if kind and kind ~= "" then
      io.write("accept\n")
    else
      io.write("print-query\n")
    end
    return
  end
  os.remove(config.fire_mode_file)
  local prompt = util.read_file(config.prompt_file) or " "
  local target = util.read_file(config.fire_pane_file)
  local kind_id = util.read_file(config.fire_kind_file)
  local expected_pid = util.read_file(config.fire_pid_file)
  if target then
    target = target:gsub("\n$", "")
  end
  if kind_id then
    kind_id = kind_id:gsub("\n$", "")
  end
  if expected_pid then
    expected_pid = expected_pid:gsub("\n$", "")
  end
  os.remove(config.fire_pane_file)
  os.remove(config.fire_kind_file)
  os.remove(config.fire_pid_file)

  local notice
  if not target or target == "" then
    notice = config.busy_color .. "not sent (no agent)" .. config.reset
  elseif not msg or msg:match("^%s*$") then
    notice = config.busy_color .. "not sent (empty)" .. config.reset
  else
    local pane_id = "%" .. target
    local adapter, status = registry.read_status(pane_id)
    local state = adapter and adapter.read_state and adapter.read_state(pane_id)
    if not adapter or adapter.id ~= kind_id or not status or not state
      or tostring(state.pid) ~= expected_pid then
      notice = config.busy_color .. "not sent (no agent)" .. config.reset
    else
      local ok, err = adapter.fire(pane_id, msg)
      if ok then
        notice = config.agent_color .. "sent → " .. target .. config.reset
      elseif err == "empty" then
        notice = config.busy_color .. "not sent (empty)" .. config.reset
      else
        notice = config.busy_color .. "not sent (send-keys)" .. config.reset
      end
    end
  end

  io.write(string.format(
    "change-prompt(%s)+clear-query+change-header(%s)\n",
    prompt,
    header(notice)
  ))
end

function M.esc()
  local prompt = util.read_file(config.prompt_file) or " "
  if not util.file_exists(config.fire_mode_file) then
    io.write("abort\n")
    return
  end
  os.remove(config.fire_mode_file)
  os.remove(config.fire_pane_file)
  os.remove(config.fire_kind_file)
  os.remove(config.fire_pid_file)
  local notice = config.busy_color .. "not sent" .. config.reset
  io.write(string.format(
    "change-prompt(%s)+clear-query+change-header(%s)\n",
    prompt,
    header(notice)
  ))
end

function M.clear_state()
  os.remove(config.fire_mode_file)
  os.remove(config.fire_pane_file)
  os.remove(config.fire_kind_file)
  os.remove(config.fire_pid_file)
end

return M
