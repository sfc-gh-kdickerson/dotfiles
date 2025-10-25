local dashboard_width_percentage = 0.35
local dashboard_width = math.floor(vim.api.nvim_win_get_width(0) * dashboard_width_percentage)

local image_dimentions = {
  width = dashboard_width,
  height = 25,
}
return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@module "snacks"
  ---@type snacks.Config
  opts = {
    dashboard = {
      width = dashboard_width,
      preset = {
        keys = {
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },

      sections = {
        -- {
        --   section = "terminal",
        --   cmd = "chafa ~/dotfiles/.config/nvim/lua/kaleb/plugins/assets/WoR.jpg --format symbols --symbols vhalf --size " .. image_dimentions.width .. "x" .. image_dimentions.height .. " --stretch; sleep .1",
        --   height = image_dimentions.height,
        --   padding = 1,
        -- },
        { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')", padding = 1 },
        {
          icon = " ",
          key = "c",
          desc = "Config",
          action = ":lua Snacks.dashboard.pick('files', {cwd = '~/dotfiles'})",
          padding = 1,
        },
        {
          icon = " ",
          key = "b",
          desc = "Browse Repo",
          action = function()
            Snacks.gitbrowse()
          end,
          padding = 1,
        },
        {
          icon = " ",
          desc = "Open Neogit",
          padding = 1,
          key = "n",
          action = function()
            require("neogit").open()
          end,
        },
        { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
        -- {
        --   icon = " ",
        --   title = "Git Status",
        --   section = "terminal",
        --   enabled = function()
        --     return Snacks.git.get_root() ~= nil
        --   end,
        --   cmd = "git status --short --branch --renames",
        --   height = 5,
        --   padding = 1,
        --   ttl = 5 * 60,
        --   indent = 3,
        -- },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
