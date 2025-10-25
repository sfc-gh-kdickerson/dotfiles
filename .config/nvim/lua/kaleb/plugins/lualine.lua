local utils = require("kaleb.utils")

return {
  {
    "nvim-lualine/lualine.nvim",
    event = "BufReadPre",
    dependencies = {
      {
        "milanglacier/minuet-ai.nvim",
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
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics", "harpoon2", "searchcount" },
          lualine_c = {
            "filename",
          },
          lualine_x = {
            utils.python_venv,
          },
          lualine_y = {
            {
              require("minuet.lualine"),
              display_on_idle = true,
            },
            "lsp_status",
            "progress",
          },
          lualine_z = { "location" },
        },
      })
    end,
  },
}
