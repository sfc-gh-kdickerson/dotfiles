vim.filetype.add({
  extension = {
    ["http"] = "http",
  },
})

return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    config = function()
      vim.keymap.set("n", "<CR>", function()
        require("kulala").run()
      end, { buffer = 0, noremap = true, silent = true })
      require("kulala").setup({})
    end,
  },
}
