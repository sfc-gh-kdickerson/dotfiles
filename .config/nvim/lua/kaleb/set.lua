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

vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking text",
  group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})
