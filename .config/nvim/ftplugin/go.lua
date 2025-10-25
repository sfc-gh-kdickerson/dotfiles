vim.api.nvim_create_autocmd("BufWritePre", {
  buffer = 0, -- Apply to the current buffer
  callback = function()
    vim.lsp.buf.format({ async = false, timeout_ms = 1000 })
  end,
})
