local utils = require("kaleb.utils")

return {
  before_init = function(_, config)
    local bufname = vim.api.nvim_buf_get_name(0)
    local start = bufname ~= "" and bufname or config.root_dir
    config.settings = config.settings or {}
    if start and start ~= "" then
      utils.apply_pyright_settings(config.settings, start)
    end
  end,
  settings = {
    python = {
      pythonPath = utils.get_python_path(),
      analysis = {
        extraPaths = utils.python_analysis_paths(),
        typeCheckingMode = "basic",
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly",
        useLibraryCodeForTypes = true,
        reportMatchNotExhaustive = true,
        exclude = {
          ".github",
          ".git",
        },
        inlayHints = {
          variableTypes = true,
          functionReturnTypes = true,
          parameterNames = true,
          callArgumentTypes = true,
        },
      },
    },
  },
}
