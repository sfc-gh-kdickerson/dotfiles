local config = require("config")
local util = require("util")
local sesh = require("sesh")
local git = require("git")
local tmux = require("tmux")
local registry = require("agents.registry")

local M = {}

local function agent_loc(session, win_index, win_name)
  local loc = session .. ":" .. win_index
  if win_name and win_name ~= "" and win_name ~= "Window" and win_name ~= win_index then
    loc = loc .. "/" .. win_name
  end
  return loc
end

local function pane_loc(session, win_name)
  if not win_name or win_name == "" or win_name == "Window" then
    return session
  end
  return session .. "/" .. win_name
end

function M.panes()
  local allowed = sesh.allowed_sessions()
  for _, row in ipairs(tmux.list_panes(
    "#{session_name}\t#{pane_id}\t#{window_name}\t#{pane_current_command}\t#{pane_current_path}"
  )) do
    local session, pane_id, win_name, cmd, path = util.split_tab(row, 5)
    if session and allowed[session] then
      local loc = pane_loc(session, win_name)
      local cmd_disp = cmd
      if registry.is_agent_command(cmd) then
        cmd_disp = config.agent_color .. cmd .. config.reset
      end
      local display = loc .. "  " .. cmd_disp
      util.emit({
        kind = "pane",
        target = pane_id,
        name = display,
        extra = git.decorate(git.ref(path)),
      })
    end
  end
end

function M.agents(ready_only)
  local rows = {}
  for _, row in ipairs(tmux.list_panes(
    "#{session_name}\t#{pane_id}\t#{window_index}\t#{window_name}\t#{pane_current_path}"
  )) do
    local session, pane_id, win_index, win_name, path = util.split_tab(row, 5)
    if session then
      local adapter, st = registry.read_status(pane_id)
      if adapter and st and (not ready_only or st == "ready") then
        local order = 1
        if st == "ready" then
          order = 0
        end
        local st_disp = config.agent_color .. st .. config.reset
        if st ~= "ready" then
          st_disp = config.busy_color .. st .. config.reset
        end
        local display = agent_loc(session, win_index, win_name) .. "  " .. st_disp
        local title = adapter.title(pane_id)
        if title and title ~= "" then
          display = display .. "  " .. title
        end
        rows[#rows + 1] = {
          order = order,
          pane_id = pane_id,
          display = display,
          extra = git.decorate(git.ref(path)),
        }
      end
    end
  end
  table.sort(rows, function(a, b)
    return a.order < b.order
  end)
  for _, row in ipairs(rows) do
    util.emit({
      kind = "agent",
      target = row.pane_id,
      name = row.display,
      extra = row.extra,
    })
  end
end

function M.preview_path(path)
  if not path or path == "" then
    return
  end
  io.write(config.branch_color, path, config.reset, "\n")
  local ref = git.ref(path)
  if ref then
    io.write(config.branch_color, config.git_icon, " ", ref, config.reset, "\n")
  end
end

function M.preview_session(session, source)
  if not session or session == "" then
    return
  end
  if source and source ~= "" and source ~= "tmux" then
    M.preview_path(session)
    return
  end
  local windows = tmux.list_windows(
    session,
    "#{window_index}\t#{window_name}\t#{window_layout}\t#{window_active}"
  )
  if #windows == 0 then
    io.write(config.branch_color, session, config.reset, "\n")
    return
  end

  io.write(config.branch_color, session, config.reset, "\n")
  for _, row in ipairs(windows) do
    local index, name, layout, active = util.split_tab(row, 4)
    if index then
      local marker = "○"
      if active == "1" then
        marker = config.agent_color .. "●" .. config.reset
      end
      io.write(
        "\n",
        marker,
        " ",
        config.agent_color,
        "window ",
        index,
        config.reset,
        "  ",
        name or "",
        "  ",
        config.branch_color,
        layout or "",
        config.reset,
        "\n"
      )
      for _, pane_row in ipairs(tmux.list_window_panes(
        session .. ":" .. index,
        "#{pane_index}\t#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_width}x#{pane_height}\t#{pane_current_path}\t#{pane_active}"
      )) do
        local pane, pane_id, command, title, size, path, pane_active =
          util.split_tab(pane_row, 7)
        if pane then
          local pane_marker = " "
          if pane_active == "1" then
            pane_marker = config.agent_color .. "▸" .. config.reset
          end
          local pane_label = command or ""
          if title and title ~= "" and title ~= pane_label then
            pane_label = pane_label .. "  " .. title
          end
          local ref = git.ref(path)
          io.write(
            "  ",
            pane_marker,
            " ",
            config.branch_color,
            "pane ",
            pane,
            config.reset,
            "  ",
            pane_label,
            "  ",
            size or "",
            "  ",
            pane_id or "",
            "\n    ",
            path or "",
            ref and ("  " .. config.branch_color .. config.git_icon .. " " .. ref .. config.reset) or "",
            "\n"
          )
        end
      end
    end
  end
end

function M.preview_pane(pane_id)
  local pane = tmux.norm_pane(pane_id)
  if not pane then
    return
  end

  local info = tmux.pane_info(
    pane,
    "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_index}\t"
      .. "#{pane_title}\t#{pane_current_command}\t#{pane_width}x#{pane_height}\t"
      .. "#{pane_current_path}\t#{pane_active}\t#{window_active}"
  )
  if not info then
    io.write(config.busy_color, "pane unavailable", config.reset, "\n")
    return
  end

  local session, win_index, win_name, pane_index, title, command, size, path,
    pane_active, window_active = util.split_tab(info, 10)
  local marker = "○"
  if pane_active == "1" then
    marker = config.agent_color .. "●" .. config.reset
  end
  local location = (session or "") .. ":" .. (win_index or "")
  if win_name and win_name ~= "" and win_name ~= "Window" then
    location = location .. "/" .. win_name
  end
  location = location .. "  pane " .. (pane_index or "")

  io.write(marker, " ", config.agent_color, location, config.reset, "\n")
  io.write(
    config.branch_color,
    command or "",
    config.reset,
    "  ",
    size or "",
    "  ",
    pane,
    window_active == "1" and "  active window" or "",
    "\n"
  )
  if title and title ~= "" and title ~= command then
    io.write("title  ", title, "\n")
  end
  if path and path ~= "" then
    local ref = git.ref(path)
    io.write(
      "path   ",
      path,
      ref and ("  " .. config.branch_color .. config.git_icon .. " " .. ref .. config.reset) or "",
      "\n"
    )
  end

  local function tail_lines(text, count)
    local rows = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
      rows[#rows + 1] = line
    end
    while #rows > count do
      table.remove(rows, 1)
    end
    while #rows > 1 and rows[#rows]:match("^%s*$") do
      table.remove(rows)
    end
    return table.concat(rows, "\n")
  end

  local capture = tmux.capture_pane(pane, -120)
  if capture and capture ~= "" then
    local preview_lines = tonumber(os.getenv("FZF_PREVIEW_LINES")) or 24
    preview_lines = math.max(1, math.floor(preview_lines) - 7)
    io.write("\n", tail_lines(capture, preview_lines), "\n")
  else
    io.write("\n", config.branch_color, "(empty pane)", config.reset, "\n")
  end
end

function M.relist(kind)
  if kind == "pane" or kind == "panes" then
    M.panes()
  elseif kind == "agent" or kind == "agents" then
    M.agents()
  elseif kind == "agents-ready" then
    M.agents(true)
  else
    sesh.list_sessions("-t -H")
  end
end

function M.current(view)
  if view == "agents" then
    M.agents()
  elseif view == "agents-ready" then
    M.agents(true)
  elseif view == "panes" then
    M.panes()
  elseif view == "zoxide" then
    sesh.list_sessions("-z")
  elseif view == "all" then
    sesh.list_sessions("")
  else
    sesh.list_sessions("-t -H")
  end
end

return M
