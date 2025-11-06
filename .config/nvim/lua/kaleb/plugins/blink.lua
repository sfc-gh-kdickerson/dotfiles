vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })

return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "folke/lazydev.nvim",
      {
        "xzbdmw/colorful-menu.nvim",
        config = function()
          require("colorful-menu").setup({})
        end,
      },
      {
        "L3MON4D3/LuaSnip",
        dependencies = { "rafamadriz/friendly-snippets" },
        version = "v2.*",
        build = "make install_jsregexp",
        config = function()
          require("luasnip.loaders.from_vscode").lazy_load()
        end,
      },
    },
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    --- @module "blink.cmp"
    --- @type blink.cmp.Config
    opts = {
      keymap = {
        ["<C-u>"] = { "scroll_documentation_up", "hide_documentation" },
        ["<C-d>"] = { "scroll_documentation_down", "hide_documentation" },
        ["<C-e>"] = { "show", "hide", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "fallback" },
        ["<S-Tab>"] = { "fallback" },
        ["<C-f>"] = { "snippet_forward", "fallback" },
        ["<C-b>"] = { "snippet_backward", "fallback" },
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },
        ["<Esc>"] = { "cancel", "fallback" },
      },
      snippets = { preset = "luasnip" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "lazydev" },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
          },
        },
      },
      -- experimental signature help support
      signature = { enabled = true, window = { border = "rounded", show_documentation = true } },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 100 },
        accept = { auto_brackets = { enabled = true } },
        list = {
          selection = {
            preselect = function(ctx)
              -- disable preselect in markdown and python files
              local filetype = vim.bo[ctx.bufnr].filetype
              if (filetype == "markdown") or (filetype == "python") then
                return false
              end
              return true
            end,
            auto_insert = true,
          },
        },
        menu = {
          draw = {
            -- We don't need label_description now because label and label_description are already
            -- combined together in label by colorful-menu.nvim.
            columns = { { "label", gap = 1 }, { "kind_icon", "kind", gap = 1 } },
            components = {
              label = {
                text = function(ctx)
                  return require("colorful-menu").blink_components_text(ctx)
                end,
                highlight = function(ctx)
                  return require("colorful-menu").blink_components_highlight(ctx)
                end,
              },
            },
          },
        },
        -- menu = {
        --   min_width = 20,
        --   max_height = 15,
        --   border = "rounded",
        --   -- Keep the cursor X lines away from the top/bottom of the window
        --   scrolloff = 2,
        --   -- Note that the gutter will be disabled when border ~= 'none'
        --   scrollbar = false,
        --   -- Controls how the completion items are rendered on the popup window
        --   draw = {
        --     -- Use treesitter to highlight the label text of completions from these sources
        --     treesitter = { "lsp" },
        --     -- for a setup similar to nvim-cmp: https://github.com/Saghen/blink.cmp/pull/245#issuecomment-2463659508
        --     columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind", gap = 1 } },
        --   },
        -- },
      },
      cmdline = {
        keymap = {
          preset = "inherit",
        },
        completion = {
          list = {
            selection = {
              preselect = false,
            },
          },
          menu = {
            auto_show = true,
          },
        },
      },
      appearance = {
        nerd_font_variant = "mono",
      },
      formatting = {
        format = function(entry, vim_item)
          local ok, colorful_menu = pcall(require, "colorful-menu")
          if not ok then
            return vim_item
          end
          local highlights_info = colorful_menu.cmp_highlights(entry)
          if highlights_info ~= nil then
            vim_item.abbr_hl_group = highlights_info.highlights
            vim_item.abbr = highlights_info.text
          end
          return vim_item
        end,
      },
    },
    opts_extend = { "sources.default" },
  },
}
