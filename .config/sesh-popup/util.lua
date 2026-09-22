local config = require("config")

local M = {}
local unpack_values = table.unpack or unpack

function M.die(msg)
  os.execute(
    "PATH=" .. M.shell_quote(config.path_prefix)
      .. " tmux display-message "
      .. M.shell_quote("sesh-popup: " .. msg)
      .. " 2>/dev/null"
  )
  io.stderr:write("sesh-popup: ", msg, "\n")
  os.exit(1)
end

function M.need(cmd)
  local h = io.popen(
    "PATH=" .. M.shell_quote(config.path_prefix)
      .. " command -v " .. M.shell_quote(cmd) .. " 2>/dev/null"
  )
  if not h then
    M.die(cmd .. " not found")
  end
  local ok = h:read("*a")
  h:close()
  if not ok or ok == "" then
    M.die(cmd .. " not found")
  end
end

function M.run(cmd)
  local h = io.popen(cmd)
  if not h then
    return nil
  end
  local out = h:read("*a")
  local ok = h:close()
  if not ok then
    return nil
  end
  return out
end

function M.lines(cmd)
  local out = M.run(cmd)
  if not out then
    return {}
  end
  local rows = {}
  for line in out:gmatch("[^\n]+") do
    rows[#rows + 1] = line
  end
  return rows
end

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.chop_title(s)
  s = s:gsub("[\r\n]+", "  "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #s > 80 then
    return s:sub(1, 80)
  end
  return s
end

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

function M.write_file(path, data)
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(data)
  f:close()
  return true
end

function M.file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

function M.norm_pane(pane)
  if not pane or pane == "" then
    return nil
  end
  pane = pane:gsub("^%%", "")
  if pane == "" then
    return nil
  end
  return "%" .. pane
end

function M.pane_num(pane)
  return (pane or ""):gsub("^%%", "")
end

function M.split_tab(line, max_fields)
  local fields = {}
  local start = 1
  local limit = max_fields and math.max(1, max_fields - 1) or math.huge
  while #fields < limit do
    local finish = line:find("\t", start, true)
    if not finish then
      break
    end
    fields[#fields + 1] = line:sub(start, finish - 1)
    start = finish + 1
  end
  fields[#fields + 1] = line:sub(start)
  return unpack_values(fields)
end

function M.clean_field(value)
  local cleaned = tostring(value or ""):gsub("[\r\n\t]", " ")
  return cleaned
end

function M.shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Picker row: kind, target, name, source, extra (git branch). fzf shows 3+5
-- and searches both; source stays in field 4 for session preview.
function M.emit(row)
  io.write(table.concat({
    M.clean_field(row.kind),
    M.clean_field(row.target),
    M.clean_field(row.name),
    M.clean_field(row.source),
    M.clean_field(row.extra),
  }, config.tab), "\n")
end

return M
