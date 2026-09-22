local config = require("config")

local M = {}

local adapters = {}
local adapter_order = {}
for _, id in ipairs(config.agent_adapters) do
  local adapter = require("agents." .. id)
  adapters[adapter.id] = adapter
  adapter_order[#adapter_order + 1] = adapter
end

local by_command = {}

for _, adapter in ipairs(adapter_order) do
  for _, cmd in ipairs(adapter.commands) do
    by_command[cmd] = adapter
  end
end

function M.all()
  return adapters
end

function M.get(id)
  return adapters[id]
end

function M.for_command(cmd)
  return by_command[cmd]
end

function M.is_agent_command(cmd)
  return by_command[cmd] ~= nil
end

-- First adapter whose state file validates for this pane wins.
function M.for_pane(pane_id)
  for _, adapter in ipairs(adapter_order) do
    local status = adapter.read_status(pane_id)
    if status then
      return adapter, status
    end
  end
  return nil
end

function M.read_status(pane_id)
  return M.for_pane(pane_id)
end

return M
