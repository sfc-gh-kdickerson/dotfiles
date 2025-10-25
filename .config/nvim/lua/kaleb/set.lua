COLORSCHEME = "catppuccin-mocha"

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
-- Enable persistent undo
vim.opt.undofile = true
-- Set the undo directory
vim.opt.undodir = vim.fn.expand("~/.local/share/nvim/undo")
-- Enable autoread when files are changed outside of Neovim
vim.opt.autoread = true
vim.o.splitright = true
-- Needed for Obisidian
vim.opt.conceallevel = 1
vim.o.winborder = "rounded"

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "✘",
      [vim.diagnostic.severity.WARN] = "",
      [vim.diagnostic.severity.HINT] = "",
      [vim.diagnostic.severity.INFO] = "",
    },
  },
})

local highlight_yank_group = vim.api.nvim_create_augroup("HighlightYank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = highlight_yank_group,
  desc = "Highlight when yanking text",
  callback = function()
    vim.highlight.on_yank()
  end,
})

local macro_augroup = vim.api.nvim_create_augroup("MacroRecordingNotifier", { clear = true })

-- Notification for when recording starts
vim.api.nvim_create_autocmd("RecordingEnter", {
  group = macro_augroup,
  callback = function()
    local register = vim.fn.reg_recording()
    -- 4. Send the notification
    vim.notify(
      string.format("Recording Macro @%s", register),
      vim.log.levels.INFO,
      { title = "Macro Recording Started" }
    )
  end,
})

-- Notification for when recording stops
vim.api.nvim_create_autocmd("RecordingLeave", {
  group = macro_augroup,
  callback = function()
    vim.notify("Macro Recording Finished", vim.log.levels.INFO, { title = "Macro Recording Complete" })
  end,
})
