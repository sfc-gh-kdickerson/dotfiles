vim.keymap.set("i", "'", "'", { buffer = 0 })
vim.api.nvim_set_hl(0, '@lsp.type.variable.rust', { link = '@variable' })
