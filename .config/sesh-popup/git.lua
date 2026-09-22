local config = require("config")
local util = require("util")

local M = {}

-- Leading space + tabstop=1 makes the picker gap match the old "  icon ref".
function M.decorate(ref)
  if not ref or ref == "" then
    return ""
  end
  return " " .. config.branch_color .. config.git_icon .. " " .. ref .. config.reset
end

function M.ref(path)
  if not path or path == "" then
    return nil
  end
  local ref = util.run("git -C " .. util.shell_quote(path) .. " branch --show-current 2>/dev/null")
  if ref then
    ref = util.trim(ref)
  end
  if not ref or ref == "" then
    ref = util.run(
      "git -C " .. util.shell_quote(path) .. " describe --tags --exact-match 2>/dev/null"
    )
    if ref then
      ref = util.trim(ref)
    end
  end
  if ref and ref ~= "" then
    return ref
  end
  return nil
end

return M
