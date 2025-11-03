vim.api.nvim_create_autocmd("User", {
  pattern = "MiniFilesActionRename",
  callback = function(event)
    Snacks.rename.on_rename_file(event.data.from, event.data.to)
  end,
})
-- needed for image to know in kitty
vim.env.TERM = "exterm-kitty"

vim.api.nvim_create_user_command("Zen", function()
  Snacks.zen()
end, { desc = "Zen" })

local dimmed = false
vim.api.nvim_create_user_command("Dim", function()
  if not dimmed then
    Snacks.dim.enable()
  else
    Snacks.dim.disable()
  end
  dimmed = not dimmed
end, { desc = "Dim" })


return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@module "snacks"
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    rename = { enabled = true },
    quickfile = { enabled = true },
    zen = { enabled = true },
    dim = { enabled = true },
    animate = { enabled = true },
    statuscolumn = { enabled = true, left = { "git", "mark" }, right = { "sign", "fold" } },
    input = { enabled = true, b = { completion = true } },
    image = { enabled = true },
    indent = { enabled = true, scope = { hl = "NormalFloat" } },
    scope = { enabled = true },
    bufdelete = { enabled = true },
  },
  keys = {
    -- stylua: ignore start
    --
    { "<leader>bd", function() Snacks.bufdelete.delete() end, desc = "delete current buffer" },
    --
    -- stylua: ignore end
  },
}
