return {
  settings = {
    ["rust-analyzer"] = {
      checkOnSave = {
        enable = true,
        command = "clippy",
      },

      inlayHints = {
        lifetimeElisionHints = {
          enable = false,
        },
        bindingModeHints = {
          enable = false,
        },
        closureReturnTypeHints = {
          enable = "never",
        },
        expressionAdjustmentHints = {
          enable = false,
        },

        -- Enables type hints, but we'll hide everything except function-call parameter types
        typeHints = {
          enable = false,

          -- Keep only function-call style hints visible:
          hideNamedConstructor = true,
          hideClosureInitialization = true,
        },

        -- Show parameter hints for function calls
        parameterHints = {
          enable = true,
        },
      },
    },
  },
}
