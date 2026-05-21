return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local install_parsers = {
        "bash",
        "go",
        "http",
        "java",
        "json",
        "latex",
        "python",
        "rust",
        "toml",
        "yaml",
        "zig",
      }

      vim.treesitter.language.register("bash", "sh")
      vim.treesitter.language.register("bash", "zsh")
      vim.filetype.add({ extension = { ebnf = "ebnf" } })
      vim.filetype.add({ extension = { conf = "toml" } })
      vim.filetype.add({ extension = { ftl = "ftl" } })
      vim.filetype.add({ extension = { http = "http" } })
      vim.filetype.add({ extension = { log = "json" } })

      local treesitter = require("nvim-treesitter")
      treesitter.setup({
        install_dir = vim.fn.stdpath("data") .. "/site",
      })

      vim.api.nvim_create_user_command("TSInstallConfigured", function()
        local installs = treesitter.install(install_parsers)
        if installs and installs.wait then
          installs:wait(300000)
        end
      end, { desc = "Install configured Tree-sitter parsers" })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
        pattern = {
          "bash",
          "c",
          "conf",
          "go",
          "http",
          "java",
          "json",
          "latex",
          "lua",
          "markdown",
          "python",
          "rust",
          "sh",
          "toml",
          "vim",
          "yaml",
          "zig",
          "zsh",
        },
        callback = function(args)
          local max_filesize = 100 * 1024 -- 100 KB
          local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
          if ok and stats and stats.size > max_filesize then
            return
          end

          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    enabled = false,
    lazy = true,
    config = function()
      local treesitter_context = require("treesitter-context")
      treesitter_context.setup({
        enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
        multiwindow = false, -- Enable multiwindow support.
        max_lines = 5, -- How many lines the window should span. Values <= 0 mean no limit.
        multiline_threshold = 3,
        trim_scope = "outer", -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
        mode = "cursor", -- Line used to calculate context. Choices: 'cursor', 'topline'
        -- Separator between context and content. Should be a single character string, like '-'.
        -- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
        separator = nil,
      })
    end,
  },
}
