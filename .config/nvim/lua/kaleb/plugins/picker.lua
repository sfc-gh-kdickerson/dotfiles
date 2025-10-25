local picker_ignore = vim.fn.getcwd() .. "/.nvim/.pickerignore"
local picker_ignore_patterns = {}
if vim.fn.filereadable(picker_ignore) == 1 then
  picker_ignore_patterns = vim.fn.readfile(picker_ignore)
end

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@module "snacks"
  ---@type snacks.Config
  opts = {
    explorer = { enabled = true, replace_netrw = false },
    picker = {
      enabled = true,
      sources = {
        files = { hidden = true },
        grep = { hidden = true },
        explorer = { auto_close = true, hidden = true },
      },
    },
  },
  keys = {
    -- stylua: ignore start
    --
    -- picker -- 
    -- super powerful general purpose finder
    { "<leader>e", function() Snacks.explorer() end, desc = "File Explorer" },
    { "<leader><space>", function() Snacks.picker.smart({ cwd = vim.fn.getcwd() }) end, desc = "Smart Find Files" },

    -- finders - with the intent of finding/going somewhere
    { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
    { "<leader>fc", function() Snacks.picker.files({ cwd = "~/dotfiles" }) end, desc = "Find Config File" },
    { "<leader>ff", function()
      Snacks.picker.files({ exclude=picker_ignore_patterns })
    end, desc = "Find Files" },
    { "<leader>fl", function() Snacks.picker.lines() end, desc = "Buffer Lines" },
    { "<leader>fs", function() Snacks.picker.grep() end, desc = "Grep" },
    { "<leader>fw", function() Snacks.picker.grep_word() end, desc = "Visual selection or word", mode = { "n", "x" } },
    { '<leader>f/', function() Snacks.picker.search_history() end, desc = "Search History" },
    { '<leader>fS', function() Snacks.picker.lsp_symbols() end, desc = "Lsp Symbols" },
    { "<leader>fD", function() Snacks.picker.diagnostics() end, desc = "Diagnostics" },
    { "<leader>fd", function() Snacks.picker.diagnostics_buffer() end, desc = "Buffer Diagnostics" },
    { "<leader>fh", function() Snacks.picker.help() end, desc = "Help Pages" },
    { "<leader>fq", function() Snacks.picker.qflist() end, desc = "Quickfix List" },

    -- searches - with the intent of searching for information
    { "<leader>sc", function() Snacks.picker.command_history() end, desc = "Command History" },
    { "<leader>sC", function() Snacks.picker.commands() end, desc = "Commands" },
    { "<leader>sk", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
    { "<leader>su", function() Snacks.picker.undo() end, desc = "Undo History" },
    { "<leader>ss", function() Snacks.picker.lsp_symbols() end, desc = "LSP Symbols" },
    { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "LSP Workspace Symbols" },

    -- git
    { "<leader>gb", function() Snacks.picker.git_branches() end, desc = "Git Branches" },
    { "<leader>gl", function() Snacks.picker.git_log() end, desc = "Git Log" },


    -- lsp stuff --
    { "gd", function() Snacks.picker.lsp_definitions() end, desc = "Goto Definition" },
    { "gD", function() Snacks.picker.lsp_declarations() end, desc = "Goto Declaration" },
    { "gr", function() Snacks.picker.lsp_references() end, nowait = true, desc = "References" },
    { "gI", function() Snacks.picker.lsp_implementations() end, desc = "Goto Implementation" },
    { "gy", function() Snacks.picker.lsp_type_definitions() end, desc = "Goto T[y]pe Definition" },

    -- { "<leader>,", function() Snacks.picker.buffers() end, desc = "Buffers" },
    -- { "<leader>/", function() Snacks.picker.grep() end, desc = "Grep" },
    -- { "<leader>:", function() Snacks.picker.command_history() end, desc = "Command History" },
    -- { "<leader>n", function() Snacks.picker.notifications() end, desc = "Notification History" },
    -- { "<leader>fg", function() Snacks.picker.git_files() end, desc = "Find Git Files" },
    -- { "<leader>fp", function() Snacks.picker.projects() end, desc = "Projects" },
    -- { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent" },
    -- { "<leader>gL", function() Snacks.picker.git_log_line() end, desc = "Git Log Line" },
    -- { "<leader>gs", function() Snacks.picker.git_status() end, desc = "Git Status" },
    -- { "<leader>gS", function() Snacks.picker.git_stash() end, desc = "Git Stash" },
    -- { "<leader>gd", function() Snacks.picker.git_diff() end, desc = "Git Diff (Hunks)" },
    -- { "<leader>gf", function() Snacks.picker.git_log_file() end, desc = "Git Log File" },
    -- { "<leader>fs", function() Snacks.picker.grep_buffers() end, desc = "Grep Open Buffers" },
    -- { '<leader>s"', function() Snacks.picker.registers() end, desc = "Registers" },
    -- { "<leader>sa", function() Snacks.picker.autocmds() end, desc = "Autocmds" },
    -- { "<leader>sb", function() Snacks.picker.lines() end, desc = "Buffer Lines" },
    -- { "<leader>sH", function() Snacks.picker.highlights() end, desc = "Highlights" },
    -- { "<leader>si", function() Snacks.picker.icons() end, desc = "Icons" },
    -- { "<leader>sj", function() Snacks.picker.jumps() end, desc = "Jumps" },
    -- { "<leader>sl", function() Snacks.picker.loclist() end, desc = "Location List" },
    -- { "<leader>sm", function() Snacks.picker.marks() end, desc = "Marks" },
    -- { "<leader>sM", function() Snacks.picker.man() end, desc = "Man Pages" },
    -- { "<leader>sp", function() Snacks.picker.lazy() end, desc = "Search for Plugin Spec" },
    -- { "<leader>sR", function() Snacks.picker.resume() end, desc = "Resume" },
    -- { "<leader>uC", function() Snacks.picker.colorschemes() end, desc = "Colorschemes" },
    --
    -- stylua: ignore end
  },
}
