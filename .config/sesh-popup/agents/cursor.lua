local config = require("config")
local util = require("util")
local json = require("json")
local tmux = require("tmux")
local git = require("git")

local M = {}

M.id = "cursor"
M.commands = { "agent", "cursor-agent" }

local function text(value)
  return type(value) == "string" and value or ""
end

function M.state_path(pane_id)
  return config.status_dir .. "/" .. util.pane_num(pane_id) .. ".json"
end

function M.read_state(pane_id)
  return json.read(M.state_path(pane_id))
end

function M.read_status(pane_id)
  local state = M.read_state(pane_id)
  if type(state) ~= "table" then
    return nil
  end
  if state.kind ~= M.id or state.pane_id ~= pane_id then
    return nil
  end
  local pid = state.pid
  if not pid then
    return nil
  end
  local pid_text = tostring(pid)
  if not pid_text:match("^%d+$") then
    return nil
  end
  if tonumber(pid_text) < 1 then
    return nil
  end
  if state.status ~= "ready" and state.status ~= "busy" then
    return nil
  end
  local alive = os.execute("kill -0 " .. util.shell_quote(pid_text) .. " 2>/dev/null")
  if not (alive == 0 or alive == true) then
    return nil
  end
  if not tmux.pane_owns_pid(pane_id, pid_text) then
    return nil
  end
  return state.status
end

local function conversation_id(state)
  if type(state.conversation_id) == "string" then
    return state.conversation_id
  end
  if type(state.session_id) == "string" then
    return state.session_id
  end
  return nil
end

function M.title(pane_id)
  local state = M.read_state(pane_id)
  if type(state) ~= "table" then
    return ""
  end
  local cid = conversation_id(state)
  local title
  local hist
  if cid and cid:match("^[%w%-_]+$") then
    local handle = io.popen("ls -1 "
      .. util.shell_quote(config.chats_dir) .. "/*/"
      .. util.shell_quote(cid) .. "/meta.json 2>/dev/null | head -1")
    if handle then
      local meta = handle:read("*l")
      handle:close()
      if meta and meta ~= "" then
        local meta_state = json.read(meta)
        if type(meta_state) == "table" and type(meta_state.title) == "string" then
          title = meta_state.title
        end
        hist = meta:gsub("meta%.json$", "prompt_history.json")
      end
    end
  end
  if (not title or title == "") and hist then
    local hist_state = json.read(hist)
    if type(hist_state) == "table" and type(hist_state[1]) == "string" then
      title = hist_state[1]
    end
  end
  if not title or title == "" then
    title = text(state.prompt)
  end
  return util.chop_title(title or "")
end

local function fold_line(line, width)
  local out = {}
  local i = 1
  while i <= #line do
    out[#out + 1] = line:sub(i, i + width - 1)
    i = i + width
  end
  return out
end

local function body_lines(text, width)
  local rows = {}
  for line in (text or ""):gmatch("[^\n]+") do
    if line ~= "" then
      for _, chunk in ipairs(fold_line(line, width)) do
        rows[#rows + 1] = "  " .. chunk
      end
    end
  end
  return rows
end

function M.preview(pane_id, width)
  local state = M.read_state(pane_id)
  if type(state) ~= "table" then
    return ""
  end
  width = math.max(1, math.floor(tonumber(width) or 56))
  local loc = ""
  local command
  local pane_title
  local size
  local path
  local info = tmux.pane_info(
    pane_id,
    "#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t"
      .. "#{pane_current_command}\t#{pane_title}\t#{pane_width}x#{pane_height}\t"
      .. "#{pane_current_path}"
  )
  if info then
    local session, win_index, win_name, pane
    session, win_index, win_name, pane, command, pane_title, size, path =
      util.split_tab(info, 8)
    if session then
      loc = session .. ":" .. win_index
      if win_name and win_name ~= "" and win_name ~= "Window" and win_name ~= win_index then
        loc = loc .. "/" .. win_name
      end
      loc = loc .. "  " .. (pane or pane_id)
    end
  end
  local title = M.title(pane_id)
  local st = text(state.status)
  if st == "" then
    st = "?"
  end
  local scf = config.busy_color
  if st == "ready" then
    scf = config.agent_color
  end
  local model = text(state.model):gsub("^cursor%-", "")
  local lines = {}
  local header = scf .. st .. config.reset
  if model ~= "" then
    header = header .. "  " .. config.branch_color .. model .. config.reset
  end
  local tool = text(state.tool)
  if tool ~= "" then
    header = header .. "  " .. config.branch_color .. tool .. config.reset
  end
  lines[#lines + 1] = header
  if loc ~= "" then
    lines[#lines + 1] = config.branch_color .. loc .. config.reset
  end
  if command and command ~= "" then
    local pane_meta = command
    if size and size ~= "" then
      pane_meta = pane_meta .. "  " .. size
    end
    if pane_title and pane_title ~= "" and pane_title ~= command then
      pane_meta = pane_meta .. "  " .. pane_title
    end
    lines[#lines + 1] = config.branch_color .. pane_meta .. config.reset
  end
  if path and path ~= "" then
    local ref = git.ref(path)
    lines[#lines + 1] = "path  " .. path
      .. (ref and ("  " .. config.branch_color .. config.git_icon .. " " .. ref .. config.reset) or "")
  end
  if title ~= "" then
    lines[#lines + 1] = title
  end
  local prompt = text(state.prompt)
  if prompt ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = config.branch_color .. "you" .. config.reset
    for _, row in ipairs(body_lines(prompt, width)) do
      lines[#lines + 1] = row
    end
  end
  local response = text(state.response)
  if response ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = config.branch_color .. "agent" .. config.reset
    for _, row in ipairs(body_lines(response, width)) do
      lines[#lines + 1] = row
    end
  end
  return table.concat(lines, "\n")
end

-- Cursor CLI: Enter submits; C-j is newline inside the prompt.
function M.fire(pane_id, message)
  pane_id = tmux.norm_pane(pane_id)
  if not pane_id then
    return false, "no pane"
  end
  if not message or message:match("^%s*$") then
    return false, "empty"
  end
  local first = true
  for line in (message .. "\n"):gmatch("(.-)\n") do
    if not first then
      if not tmux.send_keys(pane_id, "C-j") then
        return false, "send-keys"
      end
    end
    first = false
    if line ~= "" then
      if not tmux.send_keys(pane_id, "-l", line) then
        return false, "send-keys"
      end
    end
  end
  if not tmux.send_keys(pane_id, "Enter") then
    return false, "send-keys"
  end
  return true
end

return M
