vim.g.mapleader = " "
vim.keymap.set("i", "jj", "<Esc>", { noremap = true, silent = true })
vim.keymap.set("i", "jk", "<Esc>", { noremap = true, silent = true })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "<leader>y", "\"+y", { desc = "Yank to Register" })
vim.keymap.set("n", "<leader>Y", "\"+Y", { desc = "Yank to System Clipboard" })
vim.keymap.set("v", "<leader>y", "\"+y", { desc = "Yank to Register" })

vim.keymap.set("n", "<leader>cfp", function()
  local filepath = vim.fn.expand("%:p")
  vim.fn.setreg("+", filepath) -- write to clippoard
  print(string.format("Copied filepath:%s to clipboard!", filepath))
end)

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

vim.keymap.set("x", "<leader>p", "\"_dP")

vim.keymap.set("n", "Q", "<nop>")
-- Keep selection after indenting
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })
-- Close tab
vim.keymap.set("n", "<leader>tc", ":tabclose<CR>", { noremap = true, silent = true, desc = "Close Tab" })

-- following maps to < and > making window wider or thinner respectively
vim.keymap.set("n", "<C-W>,", function()
  local win = vim.api.nvim_get_current_win()
  local winWidth = vim.api.nvim_win_get_width(win)
  local resizeFactor = -15
  vim.api.nvim_win_set_width(win, winWidth + resizeFactor)
end, { desc = "Window a Little Smaller" })
vim.keymap.set("n", "<C-W>.", function()
  local win = vim.api.nvim_get_current_win()
  local winWidth = vim.api.nvim_win_get_width(win)
  local resizeFactor = 15
  vim.api.nvim_win_set_width(win, winWidth + resizeFactor)
end, { desc = "Window a Little Bigger" })
vim.keymap.set("n", "<C-W><", function()
  local win = vim.api.nvim_get_current_win()
  local winWidth = vim.api.nvim_win_get_width(win)
  local resizeFactor = -45
  vim.api.nvim_win_set_width(win, winWidth + resizeFactor)
end, { desc = "Window a Lot Smaller" })
vim.keymap.set("n", "<C-W>>", function()
  local win = vim.api.nvim_get_current_win()
  local winWidth = vim.api.nvim_win_get_width(win)
  local resizeFactor = 45
  vim.api.nvim_win_set_width(win, winWidth + resizeFactor)
end, { desc = "Window a Log Bigger" })

vim.keymap.set("n", "<C-s>", "ggVG", { desc = "Select All Text" })
vim.keymap.set("n", "<leader>te", ":PlenaryBustedFile %<CR>", { desc = "Plenary Test File" })

vim.keymap.set("n", "<leader>cdo", vim.diagnostic.open_float, { desc = "Code Diagnostic Open" })
