vim.filetype.add({
  extension = {
    ["http"] = "http",
  },
})

return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    keys = {
      -- stylua: ignore start
      { "<CR>", function() require("kulala").run() end, desc = "Run REST request under cursor", ft = { "http", "rest" }, },
      -- stylua: ignore end
    },
    opts = {
      ui = {
        default_view = "headers_body",
        show_icons = "signcolumn",
        win_opts = {
          wo = { foldmethod = "manual" },
        },
      },
      global_keymaps = true,
      global_keymaps_prefix = "<leader>r",
      default_env = "local",
    },
  },
}
