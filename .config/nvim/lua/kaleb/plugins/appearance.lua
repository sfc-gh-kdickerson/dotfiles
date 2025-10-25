return {
  {
    {
      "Bekaboo/dropbar.nvim",
      event = "BufReadPre",
      config = function()
        local dropbar_api = require("dropbar.api")
        vim.keymap.set("n", "<Leader>;", dropbar_api.pick, { desc = "Pick symbols in winbar" })
        vim.keymap.set("n", "[;", dropbar_api.goto_context_start, { desc = "Go to start of current context" })
        vim.keymap.set("n", "];", dropbar_api.select_next_context, { desc = "Select next context" })
      end,
    },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        transparent_background = true,
        custom_highlights = function(colors)
          return {
            ["@keyword.operator"] = { fg = colors.mauve },
          }
        end,
      })
      vim.cmd("colorscheme " .. COLORSCHEME)
    end,
  },
  -- { "j-hui/fidget.nvim", event = "LspAttach", opts = { notification = { window = { winblend = 0 } } } }, -- lsp progress messages
}
