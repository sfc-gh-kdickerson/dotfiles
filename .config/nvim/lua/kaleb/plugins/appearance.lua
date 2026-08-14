return {
  {
    {
      "Bekaboo/dropbar.nvim",
      event = "BufReadPre",
      opts = {
        sources = {
          path = {
            modified = function(sym)
              -- Peach bullet replaces the file icon when the buffer is dirty.
              return sym:merge({
                icon = "● ",
                icon_hl = "DropBarModified",
              })
            end,
          },
        },
      },
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
          enabled = false, -- dims the background color of inactive window
          shade = "dark",
          percentage = 0.15, -- percentage of the shade to apply to the inactive window
        },
        auto_integrations = true,
        transparent_background = true,
        custom_highlights = function(colors)
          return {
            ["@keyword.operator"] = { fg = colors.mauve },
            NormalNC = { bg = colors.crust },
            WinBarNC = { bg = colors.crust },
            DropBarModified = { fg = colors.peach },
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
  {
    "petertriho/nvim-scrollbar",
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = function()
      local ok, palettes = pcall(require, "catppuccin.palettes")
      if not ok then
        return { handle = { blend = 0 } }
      end
      local P = palettes.get_palette("mocha")

      -- Same vocabulary as the lualine pills: peach = focus, mauve = secondary,
      -- diagnostics and diff reuse their pill colors so the gutter and the
      -- statusline never disagree about what a warning looks like.
      local function mark(color, text)
        return { color = color, text = text }
      end

      -- Thin bar = one line, thick = several collapsed into one screen row.
      local density = { "│", "┃" }

      return {
        show_in_active_only = true, -- splits shouldn't sprout four tracks
        handle = {
          color = P.base, -- same fill as the lualine pills
          blend = 0, -- opaque; the track is chrome, not a ghost
        },
        marks = {
          Cursor = mark(P.peach, "▎"),
          Error = mark(P.red, density),
          Warn = mark(P.yellow, density),
          Info = mark(P.sky, density),
          Hint = mark(P.teal, density),
          Misc = mark(P.mauve, density),
          GitAdd = mark(P.green, "┆"),
          GitChange = mark(P.peach, "┆"),
          GitDelete = mark(P.red, "▁"),
        },
        handlers = {
          cursor = true,
          diagnostic = true,
          gitsigns = true,
          handle = true,
          search = false, -- needs hlslens, which isn't installed
        },
      }
    end,
  },
}
