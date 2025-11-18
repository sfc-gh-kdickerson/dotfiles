local utils = require("kaleb.utils")
vim.opt.laststatus = 0
vim.opt.cmdheight = 0

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
      require("lualine").setup({
        options = {
          theme = COLORSCHEME,
          globalstatus = true,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = {
            -- "branch",
            { "harpoon2", icon = "", padding = { left = 0, right = 1 } },
            "diff",
            "diagnostics",
            "searchcount",
          },
          lualine_c = {
            {
              "filetype",
              separator = { right = "" },
              padding = { right = 0, left = 1 },
              colored = true,
              icon_only = true,
            },
            { "filename", padding = { right = 1, left = 0 } },
          },
          lualine_x = {
            utils.python_venv,
          },

          lualine_y = {
            "kulala",
            -- "lsp_status",
            "progress",
          },
          lualine_z = { "location" },
        },
      })
    end,
  },
}
