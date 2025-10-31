return {
  {
    "github/copilot.vim",
    enabled = true,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    enabled = false,
    dependencies = {
      { "nvim-lua/plenary.nvim", branch = "master" },
    },
    build = "make tiktoken",
    opts = {},
  },
}
