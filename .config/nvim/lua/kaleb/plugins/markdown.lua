return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons", opt = true },
    ft = "markdown",
    opts = {
      -- 'hide' conceals the closing ``` line, and snacks.image anchors its
      -- inline virt_lines to exactly that line, so the image only appears when
      -- anti-conceal un-hides it under the cursor.
      -- Thin/thick borders overlay █/spaces whose highlight is fg-only
      -- (bg_as_fg) or a different paint path than the body hl_eol, so they
      -- read darker against wezterm's transparent #000000. Empty
      -- language_border keeps the language pill without a full-width █ bar.
      code = {
        border = "none",
        background_inset = 0,
        language_border = "",
        highlight_border = "RenderMarkdownCode",
        sign = false,
      },
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
