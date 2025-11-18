return {
  "folke/flash.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>j",
      mode = { "n" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
  },
  ---@type Flash.Config
  opts = {
    label = {
      uppercase = false,
      -- show the label after the match
      after = true, ---@type boolean|number[]
      -- show the label before the match
      before = false, ---@type boolean|number[]
      -- position of the label extmark
      style = "overlay", ---@type "eol" | "overlay" | "right_align" | "inline"
      -- flash tries to re-use labels that were already assigned to a position,
      -- when typing more characters. By default only lower-case labels are re-used.
      reuse = "lowercase", ---@type "lowercase" | "all" | "none"
      -- for the current window, label targets closer to the cursor first
      distance = true,
      -- minimum pattern length to show labels
      -- Ignored for custom labelers.
      min_pattern_length = 0,
    },
  },
}
