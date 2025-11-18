return {
  settings = {
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
