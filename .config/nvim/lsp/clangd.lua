return {
  cmd = {
    "clangd",
    "--background-index",
    "--suggest-missing-includes",
    "--all-scopes-completion",
    "--completion-style=detailed",
  },
  filetypes = { "c", "cpp", "hpp", "h", "objc", "objcpp", "cuda", "proto" },
}
