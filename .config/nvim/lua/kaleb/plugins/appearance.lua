return {
  {
    {
      "Bekaboo/dropbar.nvim",
      event = "BufReadPre",
      -- config = function()
      --   local dropbar_api = require("dropbar.api")
      --   vim.keymap.set("n", "<Leader>;", dropbar_api.pick, { desc = "Pick symbols in winbar" })
      --   vim.keymap.set("n", "[;", dropbar_api.goto_context_start, { desc = "Go to start of current context" })
      --   vim.keymap.set("n", "];", dropbar_api.select_next_context, { desc = "Select next context" })
      -- end,
    },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    enabled = COLORSCHEME:find("catppuccin"),
    config = function()
      require("catppuccin").setup({
        dim_inactive = {
          enabled = true, -- dims the background color of inactive window
          shade = "dark",
          percentage = 0.15, -- percentage of the shade to apply to the inactive window
        },
        auto_integrations = true,
        -- transparent_background = true,
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
          solid = false, -- Use a solid background for floating windows
        },
        integrations = {
          dropbar = {
            enabled = false,
            color_mode = false, -- enable color for kind's texts, not just kind's icons
          },
          fidget = true,
          harpoon = true,
          snacks = {
            enabled = true,
            indent_scope_color = "lavender",
          },
        },
      })
      vim.cmd("colorscheme " .. COLORSCHEME)
    end,
  },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    enabled = COLORSCHEME:find("tokyonight"),
    config = function()
      require("tokyonight").setup({
        style = "storm",
        transparent = false,
        dim_inactive = true, -- dims inactive windows
      })
      vim.cmd("colorscheme " .. COLORSCHEME)
    end,
  },
}
