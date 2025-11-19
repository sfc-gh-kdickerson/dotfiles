return {
  settings = {
    ["rust-analyzer"] = {
      checkOnSave = {
        enable = true,
        command = "clippy",
      },
    },
    inlayHints = {
      lifetimeElisionHints = {
        enable = true,
        useParameterNames = true,
      },
      bindingModeHints = {
        enable = true,
      },
      closureReturnTypeHints = {
        enable = "always",
      },
      expressionAdjustmentHints = {
        enable = true,
      },
      typeHints = {
        enable = true,
        hideClosureInitialization = false,
        hideNamedConstructor = false,
      },
    },
  },
}
