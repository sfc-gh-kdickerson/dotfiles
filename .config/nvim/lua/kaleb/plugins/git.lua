return {
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPre",
    keys = {
      { "<leader>hp", ":Gitsigns preview_hunk<CR>", desc = "Preview Hunk" },
      { "<leader>hr", ":Gitsigns reset_hunk<CR>", desc = "Reset Hunk" },
      { "<leader>hs", ":Gitsigns stage_hunk<CR>", desc = "Stage Hunk" },
      { "<leader>hd", ":Gitsigns diffthis<CR>", desc = "Diff file" },
      { "[h", ":Gitsigns prev_hunk<CR>", desc = "Hunk Backward" },
      { "]h", ":Gitsigns next_hunk<CR>", desc = "Hunk Forward" },
    },
    config = function()
      require("gitsigns").setup({
        current_line_blame = true,
        current_line_blame_opts = {
          virt_text_priority = 1,
        },
        signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
        numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
        linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
        word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
        preview_config = {
          border = "rounded",
        },
      })
      -- vim.api.nvim_create_user_command("Blame", require("gitsigns.blame").blame, {})
    end,
  },
  {
    "ruifm/gitlinker.nvim",
    event = "BufReadPre",
    dependencies = "nvim-lua/plenary.nvim",
    opts = {
      mappings = "<leader>cgl",
    },
  }, -- for copying git link to line in buffer
  {
    "sindrets/diffview.nvim",
    event = "VeryLazy",
    -- stylua: ignore start
    keys = {
      {"<leader>df", ":DiffviewFileHistory %<CR>", desc = "Diffview File"},
      {"<leader>dr", ":DiffviewFileHistory<CR>", desc = "Diffview Repo"},
      {"<leader>ds", ":DiffviewOpen<CR>", desc = "Diffview status"},
    },
    -- stylua: ignore end
    opts = {
      view = {
        -- Configure the layout and behavior of different types of views.
        -- For more info, see |diffview-config-view.x.layout|.
        merge_tool = {
          layout = "diff3_mixed",
          disable_diagnostics = true,
          winbar_info = true,
        },
      },
    },
  },
  {
    "NeogitOrg/neogit",
    -- stylua: ignore start
    keys = { { "<leader>gs", function() require("neogit").open() end, desc = "Open Neogit" } },
    -- stylua: ignore end
    dependencies = { "nvim-lua/plenary.nvim", "sindrets/diffview.nvim" },
    config = function()
      require("neogit").setup({
        kind = "auto",
        integrations = {
          diffview = true,
        },
        signs = {
          -- { CLOSED, OPENED }
          hunk = { "", "" },
          item = { "▶", "▼" },
          section = { "▶", "▼" },
        },
        status = {
          recent_commit_count = 30,
        },
        commit_editor = {
          kind = "tab",
          show_staged_diff = true,
          staged_diff_split_kind = "auto",
          spell_check = true,
        },
        process_spinner = true,
      })
      vim.api.nvim_create_autocmd({ "User" }, {
        pattern = {
          "NeogitBranchCheckout",
          "NeogitStatusRefreshed",
          "NeogitPullComplete",
          "NeogitBranchReset",
          "NeogitRebase",
          "NeogitReset",
          "NeogitMerge",
        },
        callback = function()
          vim.cmd("checktime")
        end,
      })
    end,
  },
}
