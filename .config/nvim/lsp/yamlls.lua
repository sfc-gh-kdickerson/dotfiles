return {
  settings = {
    yaml = {
      hover = true,
      validate = true,
      -- disable the schema store
      schemaStore = {
        enable = false,
        url = "",
      },
      -- manually select schemas
      schemas = {
        ["https://json.schemastore.org/kustomization.json"] = "kustomization.{yml,yaml}",
        ["https://spec.openapis.org/oas/3.1/schema/2022-10-07"] = "openapi.{yml,yaml}",
        ["/Users/kaleb/Desktop/stargate-stuff/pipelines/.vscode/stargate-schema.json"] = {
          "/Users/kaleb/Desktop/stargate-stuff/pipelines/**/*.{yml,yaml}",
          "/Users/kaleb/Desktop/endor/platform/endor-pipelines/**/*.{yml,yaml}",
        },
      },
      format = {
        enable = false,
      },
    },
  },
}
