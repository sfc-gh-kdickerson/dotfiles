return {
  "nvim-neotest/neotest",
  cmd = { "Test", "TestWatch", "TestCurrent", "TestFile" },
  keys = {
    -- stylua: ignore start
    { "TT", function() require("neotest").run.run(vim.fn.getcwd()) end, desc = "Test All" },
    { "TC", function() require("neotest").run.run() end, desc = "Test Current" },
    { "TF", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Test File" },
    { "TW", function() require("neotest").watch.toggle(vim.fn.getcwd()) end, desc = "Test Watch" },
    -- stylua: ignore end
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-lua/plenary.nvim",
    "nvim-neotest/nvim-nio",
    "nvim-neotest/neotest-python",
    "nvim-neotest/neotest-plenary",
    -- "fredrikaverpil/neotest-golang",
    "rcasia/neotest-java",
  },
  config = function()
    ---@diagnostic disable
    local neotest = require("neotest")
    neotest.setup({
      adapters = {
        require("neotest-python"),
        -- require("neotest-golang"),
        require("neotest-plenary"),
        require("neotest-java"),
      },
      quickfix = {
        enabled = true,
        open = false,
      },
    })
    ---@diagnostic enable
    vim.api.nvim_create_user_command("Test", function()
      neotest.run.run(vim.fn.getcwd())
      neotest.summary.open()
    end, {})
    vim.api.nvim_create_user_command("TestCurrent", function()
      neotest.run.run()
      neotest.summary.open()
    end, {})
    vim.api.nvim_create_user_command("TestFile", function()
      neotest.run.run(vim.fn.expand("%"))
      neotest.summary.open()
    end, {})
    vim.api.nvim_create_user_command("TestClose", function()
      neotest.summary.close()
    end, {})
    vim.api.nvim_create_user_command("TestWatch", function()
      neotest.watch.toggle(vim.fn.getcwd())
    end, {})
  end,
}
