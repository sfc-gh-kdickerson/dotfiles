return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons", opt = true },
    ft = "markdown",
    opts = {
      -- 'hide' conceals the closing ``` line, and snacks.image anchors its
      -- inline virt_lines to exactly that line, so the image only appears when
      -- anti-conceal un-hides it under the cursor.
      code = { border = "thin" },
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
