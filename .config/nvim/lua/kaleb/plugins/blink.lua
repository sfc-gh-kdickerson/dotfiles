vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })

return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "folke/lazydev.nvim",
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
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "scroll_documentation_down", "fallback" },
        ["<S-Tab>"] = { "scroll_documentation_up","fallback" },
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
        documentation = {auto_show = true , auto_show_delay_ms = 100},
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
          preset = "inherit"
        },
        completion = {
          list ={
            selection = {
              preselect = false
            }
          },
          menu = {
            auto_show = true,
          }
        },
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono",
      },
    },
    opts_extend = { "sources.default" },
  },
}
