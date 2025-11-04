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
        auto_integrations = true,
        transparent_background = true,
        custom_highlights = function(colors)
          return {
            ["@keyword.operator"] = { fg = colors.mauve },
          }
        end,
        styles = { -- Handles the styles of general hi groups (see `:h highlight-args`):
          comments = { "italic" }, -- Change the style of comments
          conditionals = { "italic" },
          loops = {},
          functions = { "italic" },
          keywords = {},
          strings = {},
          variables = {},
          numbers = {},
          booleans = {},
          properties = {},
          types = { "bold" },
          operators = {},
        },
        float = {
          transparent = true, -- Make floating windows transparent (if not overridden by NormalFloat)
          solid = false,    -- Use a solid background for floating windows
        },
      })
      vim.cmd("colorscheme " .. COLORSCHEME)
    end,
  },
}
