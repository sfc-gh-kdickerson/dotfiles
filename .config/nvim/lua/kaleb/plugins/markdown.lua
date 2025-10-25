return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons", opt = true },
    ft = "markdown",
    opts = {},
  },
  {
    -- render-markdown is more stable than markview but markview has latex rendering
    -- just using unicode characters, using it ONLY for that
    "OXY2DEV/markview.nvim",
    commit = "e2c3e56", -- some latex doesn't render if not on this commit
    ft = "markdown",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      block_quotes = { enable = false },
      callbacks = { enable = false },
      checkboxes = { enable = false },
      code_blocks = { enable = false },
      escaped = { enable = false },
      footnotes = { enable = false },
      headings = { enable = false },
      horizontal_rules = { enable = false },
      html = { enable = false },
      inline_codes = { enable = false },
      latex = { enable = true },
      links = { enable = false },
      list_items = { enable = false },
      tables = { enable = false },
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  },
}
