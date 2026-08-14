local utils = require("kaleb.utils")

return {
  {
    "nvim-lualine/lualine.nvim",
    enabled = true,
    event = "BufReadPre",
    dependencies = {
      {
        "letieu/harpoon-lualine",
        lazy = true,
        dependencies = {
          "ThePrimeagen/harpoon",
        },
      },
    },
    config = function()
      local P = require("catppuccin.palettes").get_palette("mocha")

      -- Section bg stays transparent so the %= filler is air, not a bar. That means
      -- component-internal highlights (icons, diff/diagnostic counts) inherit a
      -- transparent bg and punch holes in the pill, so every one of them names P.base.
      local transparent = { bg = "NONE", fg = P.subtext1 }
      local theme = {
        normal = { a = transparent, b = transparent, c = transparent },
        insert = { a = transparent, b = transparent, c = transparent },
        visual = { a = transparent, b = transparent, c = transparent },
        replace = { a = transparent, b = transparent, c = transparent },
        command = { a = transparent, b = transparent, c = transparent },
        terminal = { a = transparent, b = transparent, c = transparent },
        inactive = { a = transparent, b = transparent, c = transparent },
      }

      ---@param fg string accent color for the glyph
      ---@return table icon color with the pill fill behind it
      local function accent(fg)
        return { fg = fg, bg = P.base }
      end

      -- Pill = 1 space, [icon, 1 space,] content, 1 space. The right pad and the
      -- transparent gap live in fmt because lualine appends native right padding
      -- after fmt output, which would land outside the gap. Left padding is native
      -- so it applies after the icon is prepended.
      ---@param opts table
      ---@return table
      local function pill(opts)
        opts = opts or {}
        local user_fmt = opts.fmt
        local merged = vim.tbl_deep_extend("force", {
          color = { bg = P.base, fg = P.subtext1 },
          padding = { left = 1, right = 0 },
          separator = "",
        }, opts)
        merged.fmt = function(str, ctx)
          if user_fmt then
            str = user_fmt(str, ctx)
          end
          if not str or str == "" then
            return ""
          end
          return str .. " %#lualine_transparent# "
        end
        return merged
      end

      -- Idle = normal-family (n / nt / CTRL-O variants). Everything else fills the pill.
      local function is_idle_mode()
        return vim.fn.mode():sub(1, 1) == "n"
      end

      -- Peach is the default focus accent; visual/select break out to mauve.
      local mode_fills = {
        v = P.mauve,
        V = P.mauve,
        ["\22"] = P.mauve, -- CTRL-V
        s = P.mauve,
        S = P.mauve,
        ["\19"] = P.mauve, -- CTRL-S
      }

      require("lualine").setup({
        options = {
          theme = theme,
          globalstatus = true,
          component_separators = "",
          section_separators = "",
        },
        sections = {
          lualine_a = {},
          lualine_b = {},
          -- Left islands (single section so neighbors share one draw pass)
          lualine_c = {
            pill({
              "mode",
              color = function()
                if is_idle_mode() then
                  return { bg = P.base, fg = P.subtext1 }
                end
                return { bg = mode_fills[vim.fn.mode()] or P.peach, fg = P.base, gui = "bold" }
              end,
            }),
            pill({
              "harpoon2",
              icon = { "󱡅", color = accent(P.mauve) },
              indicators = { "1", "2", "3", "4" },
              active_indicators = { "1", "2", "3", "4" },
              color_active = accent(P.peach),
              no_harpoon = "",
              -- Idle marks sit in overlay0; active ones get peach from color_active.
              color = { bg = P.base, fg = P.overlay0 },
            }),
            pill({
              "diff",
              diff_color = {
                added = accent(P.green),
                modified = accent(P.peach),
                removed = accent(P.red),
              },
            }),
            pill({
              "diagnostics",
              diagnostics_color = {
                error = accent(P.red),
                warn = accent(P.yellow),
                info = accent(P.sky),
                hint = accent(P.teal),
              },
            }),
            pill({
              "searchcount",
              icon = { "󰍉", color = accent(P.yellow) },
            }),
          },
          -- Right islands
          lualine_x = {
            pill({
              utils.python_venv,
              icon = { "󰌠", color = accent(P.yellow) },
            }),
            pill({
              -- Inlined instead of the kulala component: that one hardcodes an emoji
              -- and builds its icon highlight without a bg, which holes the pill.
              function()
                if vim.bo.filetype ~= "http" then
                  return ""
                end
                local ok, config = pcall(require, "kulala.config")
                return vim.g.kulala_selected_env or (ok and config.get().default_env) or ""
              end,
              icon = { "󰖟", color = accent(P.sapphire) },
            }),
            pill({
              -- lualine's location pads to "%3d:%-2d", which reads as ragged
              -- whitespace inside a pill.
              function()
                return string.format("%d:%d", vim.fn.line("."), vim.fn.charcol("."))
              end,
              icon = { "󰍒", color = accent(P.peach) },
            }),
          },
          lualine_y = {},
          lualine_z = {},
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {},
          lualine_x = {},
          lualine_y = {},
          lualine_z = {},
        },
      })
    end,
  },
}
