-- Remap j and k to gj and gk for visual wrapped lines navigation
vim.api.nvim_buf_set_keymap(0, "n", "j", "gj", { noremap = true, silent = true })
vim.api.nvim_buf_set_keymap(0, "n", "k", "gk", { noremap = true, silent = true })
vim.opt_local.spell = true
vim.opt_local.wrap = false
