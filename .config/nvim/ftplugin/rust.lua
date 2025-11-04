vim.keymap.set("i", "'", "'", { buffer = 0 })

vim.api.nvim_create_autocmd("TextChanged", {
  buffer = 0,
  callback = function()
    print("here")
    if vim.bo.modified and not vim.bo.readonly then
      vim.cmd("silent update")
    end
  end,
  desc = "Autosave Rust on InsertLeave",
})
