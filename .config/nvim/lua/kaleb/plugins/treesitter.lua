return {
  "nvim-treesitter/nvim-treesitter",
  -- build = ":TSUpdate",
  event = "BufReadPre",
  cmd = { "TSInstall", "TSUpdate" },
  -- these actually depend on treesitter but this loads em correctly anyways
  dependencies = { "nvim-treesitter/playground", "nvim-treesitter/nvim-treesitter-context" },
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "query",
        "java",
        "go",
        "python",
        "bash",
        "yaml",
        "json",
        "latex",
        "c",
      },
      ignore_install = {},
      modules = {},
      sync_install = false,
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
        disable = function(lang, buf)
          local max_filesize = 100 * 1024 -- 100 KB
          local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
          if ok and stats and stats.size > max_filesize then
            return true
          end
        end,
      },
    })
    require("nvim-treesitter.parsers").get_parser_configs().freemarker = {
      install_info = {
        highlight = {
          url = "/Users/kaleb/Desktop/tree-sitter-freemarker",
          files = { "highlights.scm" },
        },
        url = "~/dotfiles/.config/nvim/parsers/freemarker", -- Path to the repository or directory containing your parser
        files = { "src/parser.c" }, -- Specify the source files for your parser
      },
      filetype = "ftl", -- The filetype Neovim should associate with the parser
    }

    vim.treesitter.language.register("bash", "sh")
    vim.treesitter.language.register("bash", "zsh")
    vim.treesitter.language.register("conf", "toml")
    vim.filetype.add({ extension = { ebnf = "ebnf" } })
    vim.filetype.add({ extension = { conf = "toml" } })
    vim.filetype.add({ extension = { ftl = "ftl" } })
    vim.filetype.add({ extension = { http = "http" } })
    vim.filetype.add({ extension = { log = "json" } })
  end,
}
