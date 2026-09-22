local config = require("config")
local util = require("util")

local M = {}

local function sock_cmd()
  local sock = util.read_file(config.tmux_sock_file)
  if sock and sock ~= "" then
    sock = sock:gsub("\n$", "")
    return string.format(
      "PATH=%s tmux -S %s",
      util.shell_quote(config.path_prefix),
      util.shell_quote(sock)
    )
  end
  return "PATH=" .. util.shell_quote(config.path_prefix) .. " tmux"
end

function M.cmd(args)
  return sock_cmd() .. " " .. args
end

function M.run(args)
  return util.run(M.cmd(args))
end

function M.pane_pid(pane)
  local out = M.run(string.format(
    "display-message -p -t %s '#{pane_pid}'",
    util.shell_quote(pane)
  ))
  if not out then
    return nil
  end
  return util.trim(out)
end

function M.pane_owns_pid(pane, pid)
  local pane_pid = M.pane_pid(pane)
  if not pane_pid or pane_pid == "" or not pid or pid == "" then
    return false
  end
  local p = pid
  if not tostring(p):match("^%d+$") then
    return false
  end
  for _ = 1, 8 do
    if p == pane_pid then
      return true
    end
    local out = util.run(
      "ps -o ppid= -p " .. util.shell_quote(tostring(p)) .. " 2>/dev/null"
    )
    if not out then
      break
    end
    p = util.trim(out)
    if p == "" or p == "1" then
      break
    end
  end
  return false
end

function M.norm_pane(pane)
  return util.norm_pane(pane)
end

function M.switch_pane(pane_id)
  local info = M.run(string.format(
    "display-message -p -t %s %s",
    util.shell_quote(pane_id),
    util.shell_quote("#{session_name}\t#{window_id}")
  ))
  if not info or info == "" then
    util.die("pane " .. pane_id .. " is gone")
  end
  info = util.trim(info)
  local session, win = util.split_tab(info, 2)
  if not session or not win then
    util.die("pane " .. pane_id .. " is gone")
  end
  os.execute(M.cmd("switch-client -t " .. util.shell_quote(session)))
  os.execute(M.cmd("select-window -t " .. util.shell_quote(win)))
  os.execute(M.cmd("select-pane -t " .. util.shell_quote(pane_id)))
end

function M.kill(kind, target)
  if kind == "pane" or kind == "agent" then
    os.execute(M.cmd("kill-pane -t=" .. util.shell_quote(target)))
  elseif kind == "session" then
    os.execute(M.cmd("kill-session -t=" .. util.shell_quote(target)))
  end
end

function M.send_keys(pane, ...)
  local parts = { "send-keys", "-t", pane }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = select(i, ...)
  end
  local quoted = {}
  for _, p in ipairs(parts) do
    quoted[#quoted + 1] = util.shell_quote(p)
  end
  local ok = os.execute(M.cmd(table.concat(quoted, " ")))
  return ok == 0 or ok == true
end

function M.list_panes(format)
  return util.lines(M.cmd("list-panes -a -F " .. util.shell_quote(format)))
end

function M.list_windows(session, format)
  return util.lines(M.cmd(
    "list-windows -t " .. util.shell_quote(session)
      .. " -F " .. util.shell_quote(format)
  ))
end

function M.list_window_panes(target, format)
  return util.lines(M.cmd(
    "list-panes -t " .. util.shell_quote(target)
      .. " -F " .. util.shell_quote(format)
  ))
end

function M.capture_pane(pane, start_line)
  local start = tostring(start_line or -120)
  if not start:match("^%-?%d+$") then
    start = "-120"
  end
  return M.run(
    "capture-pane -p -e -J -t " .. util.shell_quote(pane)
      .. " -S " .. util.shell_quote(start)
      .. " -E " .. util.shell_quote("-1")
  )
end

function M.pane_info(pane, format)
  local out = M.run(string.format(
    "display-message -p -t %s %s",
    util.shell_quote(pane),
    util.shell_quote(format)
  ))
  if not out then
    return nil
  end
  return (out:gsub("\r?\n$", ""))
end

function M.save_sock()
  local tmux = os.getenv("TMUX")
  if tmux then
    local sock = tmux:match("^([^,]+)")
    if sock then
      util.write_file(config.tmux_sock_file, sock .. "\n")
    end
  end
end

return M
