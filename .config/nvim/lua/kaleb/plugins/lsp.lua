local lsps = {
  "clangd",
  "markdown_oxide",
  "lua_ls",
  "bashls",
  "jsonls",
  "pyright",
  "yamlls",
  "jdtls",
  "zls",
  "rust_analyzer",
  "nil_ls",
}
vim.lsp.enable(lsps)

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local bufnr = args.buf
    -- stylua: ignore start
    vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Hover" })
    vim.keymap.set("n", "<leader>cf", function() vim.lsp.buf.format({ async = false, timeout_ms = 10000 }) end, { buffer = bufnr, desc = "Format Code" })
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr, desc = "Code Action" })
    vim.keymap.set("n", "<leader>crn", vim.lsp.buf.rename, { buffer = bufnr, desc = "Rename Symbol" })
    -- stylua: ignore end
  end,
})

vim.lsp.config("*", {
  capabilities = {
    textDocument = {
      semanticTokens = {
        multilineTokenSupport = true,
      },
      completion = {
        completionItem = {
          snippetSupport = true,
        },
      },
    },
  },
  root_markers = { ".git" },
})

return {
  {
    "williamboman/mason.nvim",
    lazy = true,
    opts = {
      registries = { "github:mason-org/mason-registry", "github:nvim-java/mason-registry" },
    },
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = true,
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      --- @diagnostic disable-next-line: missing-fields
      require("mason-lspconfig").setup({
        -- ensure_installed = lsps,
      })
    end,
  },
  {
    "nvimtools/none-ls.nvim",
    lazy = true,
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        -- debug = true,
        sources = {
          null_ls.builtins.code_actions.gitsigns,
          null_ls.builtins.formatting.black,
          null_ls.builtins.formatting.goimports,
          null_ls.builtins.formatting.isort,
          null_ls.builtins.diagnostics.mypy,
          null_ls.builtins.formatting.prettier.with({
            filetypes = {
              "javascript",
              "typescript",
              "css",
              "yaml",
              "yml",
              "markdown",
              "md",
              "txt",
            },
          }),
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.diagnostics.tidy.with({
            args = { "-errors" },
          }),
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    event = "VeryLazy",
    cmd = "Mason",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "nvimtools/none-ls.nvim",
    },
  },
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    ft = { "python", "rust" },
    priority = 1000,
    config = function()
      vim.diagnostic.config({
        virtual_text = false,
        underline = false,
        severity_sort = true,
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "●",
            [vim.diagnostic.severity.WARN] = "●",
            [vim.diagnostic.severity.HINT] = "●",
            [vim.diagnostic.severity.INFO] = "●",
          },
        },
      })
      require("tiny-inline-diagnostic").setup({
        options = {
          show_source = {
            enabled = true,
          },
          add_messages = {
            display_count = true,
          },
          multilines = {
            enabled = true,
            always_show = true,
          },
        },
      })
    end,
  },
}
