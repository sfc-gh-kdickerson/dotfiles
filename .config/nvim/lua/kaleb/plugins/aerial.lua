local editor_column_width = function()
  return vim.o.columns
end
local editor_line_height = function()
  return vim.o.lines
end
local editor_cmd_height = function()
  return vim.o.cmdheight
end

return {
  {
    "stevearc/aerial.nvim",
    keys = {
      {
        "<leader>ma",
        function()
          require("aerial").toggle({ focus = false })
        end,
        desc = "Activate Symbol Buffer View",
      },
      {
        "<leader>mf",
        function()
          require("aerial").focus()
        end,
        desc = "Focus Symbol Buffer View",
      },
    },
    event = "BufEnter",
    config = function()
      local aerial = require("aerial")
      aerial.setup({
        keymaps = {
          ["<CR>"] = function()
            aerial.select()
            aerial.open({ focus = false })
          end,
        },
        on_attach = function(bufnr)
          -- Jump forwards/backwards with '{' and '}'
          vim.keymap.set("n", "{", function()
            aerial.prev()
          end, { buffer = bufnr })
          vim.keymap.set("n", "}", function()
            aerial.next()
          end, { buffer = bufnr })
        end,
        highlight_mode = "full_width",
        icons = {
          Class = "",
          Function = "󰊕",
          Method = "󰡱",
          Interface = "",
          Namespace = "",
        },
        layout = {
          max_width = { 512, 0.4 },
          min_width = 24,
          default_direction = "float",
        },
        attach_mode = "global",
        highlight_on_hover = true,
        link_tree_to_folds = true,
        open_automatic = false,
        close_on_select = false,
        -- close_automatic_events = { "unsupported" },
        float = {
          override = function(conf, _)
            conf.relative = "editor"
            conf.anchor = "SE"
            -- conf.title = "Aerial"
            conf.col = editor_column_width()
            conf.row = editor_line_height() - editor_cmd_height() - 1
            return conf
          end,
          min_height = 1,
          max_height = { 512, 100.0 },
        },
      })

      vim.defer_fn(function()
        for _, group in ipairs(vim.fn.getcompletion("", "highlight")) do
          local kind = group:match("^Aerial(%a+)Icon$")
          if kind then
            local text = "Aerial" .. kind
            vim.api.nvim_set_hl(0, text, { link = group, default = false })
          end
        end
      end, 100)

      -- make sure aerial is resized properly when editor size changes
      vim.api.nvim_create_autocmd("VimResized", {
        callback = function()
          if aerial.is_open() then
            aerial.close()
            vim.defer_fn(function()
              aerial.open({ focus = false })
            end, 100)
          end
        end,
      })
    end,
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
  },
}
