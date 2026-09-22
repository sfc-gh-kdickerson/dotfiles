local config = require("config")
local util = require("util")
local sesh = require("sesh")
local tmux = require("tmux")

local M = {}

function M.selection(line)
  local kind, target = util.split_tab(line, 3)
  if kind == "pane" or kind == "agent" then
    tmux.switch_pane(target)
  elseif kind == "session" then
    sesh.connect(target)
  else
    sesh.connect(line)
  end
end

function M.fzf_output(text)
  local row
  local query
  for line in (text or ""):gmatch("[^\n]+") do
    if line ~= "" then
      if line:match("^session" .. config.tab)
        or line:match("^pane" .. config.tab)
        or line:match("^agent" .. config.tab) then
        row = line
      else
        query = line
      end
    end
  end
  if row then
    M.selection(row)
  elseif query then
    sesh.connect(query)
  end
end

return M
