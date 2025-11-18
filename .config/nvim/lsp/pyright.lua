local utils = require("kaleb.utils")

return {
  settings = {
    python = {
      pythonPath = utils.get_python_path(),
      analysis = {
        typeCheckingMode = "strict", -- off, basic, standard, strict
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly", -- openFilesOnly, workspace
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
