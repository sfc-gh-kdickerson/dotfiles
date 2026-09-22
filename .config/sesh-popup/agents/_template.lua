--[[
  Agent adapter template — copy to agents/<name>.lua and add "<name>" to
  config.agent_adapters.

  Required fields:
    id          stable string written to state JSON as "kind"
    commands    pane_current_command names that identify this CLI in tmux

  Required functions:
    state_path(pane_id) -> path to per-pane JSON state
    read_status(pane_id) -> "ready"|"busy"|nil
    title(pane_id) -> short row label
    preview(pane_id, width) -> multiline preview text
    fire(pane_id, message) -> ok, err

  State JSON contract (written by that agent's hooks, read by the picker):
    kind, pane_id, pid, status, updated
    optional: model, tool, prompt, response, conversation_id / session_id
]]

-- local config = require("config")
-- local M = {}
-- M.id = "example"
-- M.commands = { "example-agent" }
-- function M.state_path(pane_id) end
-- function M.read_status(pane_id) end
-- function M.title(pane_id) end
-- function M.preview(pane_id, width) end
-- function M.fire(pane_id, message) end
-- return M

return nil
