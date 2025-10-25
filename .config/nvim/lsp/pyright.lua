local utils = require("kaleb.utils")

return {
  settings = {
    python = {
      pythonPath = utils.get_python_path(),
      analysis = {
        typeCheckingMode = "basic",
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly",
        useLibraryCodeForTypes = true,
      },
    },
  },
}
