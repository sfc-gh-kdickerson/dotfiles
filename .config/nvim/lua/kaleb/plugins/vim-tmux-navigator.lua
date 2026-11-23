-- Seamless Ctrl+H/J/K/L across Neovim splits and multiplexer panes.
-- Under tmux, vim-tmux-navigator does the work. Under Rex (and not inside a
-- nested tmux), move between Neovim splits first and hand off to `rex focus`
-- at an edge. Rex's init.lua sends these keys to Neovim when it's foreground.
local function rex_bin()
  if vim.env.TMUX or not vim.env.REX_BLOCK then
    return nil
  end
  local bin = vim.env.REX_BIN_DIR and (vim.env.REX_BIN_DIR .. "/rex") or "rex"
  return vim.fn.executable(bin) == 1 and bin or nil
end

local directions = { h = "left", j = "down", k = "up", l = "right" }

local function navigate(rex, key, direction)
  local win = vim.api.nvim_get_current_win()
  pcall(vim.cmd.wincmd, key)
  if vim.api.nvim_get_current_win() == win then
    -- REX_SESSION scopes this to Neovim's own session; Rex stops at its edge.
    vim.system({ rex, "focus", direction }, { text = true }, function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          vim.notify("rex focus " .. direction .. ": " .. vim.trim(result.stderr or ""), vim.log.levels.WARN)
        end)
      end
    end)
  end
end

return {
  {
    "christoomey/vim-tmux-navigator",
    init = function()
      if rex_bin() then
        vim.g.tmux_navigator_no_mappings = 1
      end
    end,
    config = function()
      local rex = rex_bin()
      if not rex then
        return
      end
      for key, direction in pairs(directions) do
        vim.keymap.set("n", "<C-" .. key .. ">", function()
          navigate(rex, key, direction)
        end, { silent = true, desc = "Navigate " .. direction .. " (split, then Rex pane)" })
      end
    end,
  },
}
