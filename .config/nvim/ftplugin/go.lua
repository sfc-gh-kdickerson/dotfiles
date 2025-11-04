local go_fmt_group = vim.api.nvim_create_augroup("GoFmt", { clear = true })
vim.api.nvim_create_autocmd("BufWritePre", {
  group = go_fmt_group,
  buffer = 0, -- Apply to the current buffer
  callback = function()
    vim.lsp.buf.format({ async = false, timeout_ms = 1000 })
  end,
})
