local config = require("config")
local util = require("util")
local git = require("git")

local M = {}

local function safe_args(args)
  args = args or ""
  local allowed = { ["-t"] = true, ["-H"] = true, ["-z"] = true }
  local result = {}
  for token in args:gmatch("%S+") do
    if not allowed[token] then
      return ""
    end
    result[#result + 1] = token
  end
  return table.concat(result, " ")
end

local function sesh_cmd(args)
  return "PATH=" .. util.shell_quote(config.path_prefix) .. " sesh " .. args
end

function M.list(args)
  local safe = safe_args(args)
  if not safe then
    return {}
  end
  return util.lines(sesh_cmd("list " .. safe))
end

local function tmux_sessions()
  return util.lines(
    sesh_cmd("list -t --format " .. util.shell_quote("{session}"))
  )
end

function M.connect(target)
  os.execute(sesh_cmd("connect " .. util.shell_quote(target)))
end

function M.branch_table()
  local table = {}
  for _, session in ipairs(tmux_sessions()) do
    if session ~= "" then
      local path = util.run(string.format(
        "PATH=%s tmux display-message -t %s -p '#{pane_current_path}' 2>/dev/null",
        util.shell_quote(config.path_prefix),
        util.shell_quote(session .. ":")
      ))
      if path then
        path = util.trim(path)
        local ref = git.ref(path)
        if ref then
          table[session] = ref
        end
      end
    end
  end
  return table
end

function M.allowed_sessions()
  local allowed = {}
  for _, session in ipairs(tmux_sessions()) do
    if session ~= "" then
      allowed[session] = true
    end
  end
  return allowed
end

function M.list_sessions(args)
  args = safe_args(args)
  if not args then
    return
  end
  local branches = M.branch_table()
  local rows = util.lines(sesh_cmd("list --icons --format '{source}\t{session}\t{name}' " .. args))
  for _, row in ipairs(rows) do
    local src, session, name = util.split_tab(row, 3)
    if src and session and name then
      local extra = ""
      if src == "tmux" then
        extra = git.decorate(branches[session])
      end
      util.emit({
        kind = "session",
        target = session,
        name = name,
        source = src,
        extra = extra,
      })
    end
  end
end

return M
