return {
  {
    "scalameta/nvim-metals",
    ft = { "java", "scala", "sbt" },
    cmd = "GsMetalsClasspath",
    config = function()
      require("kaleb.metals").setup()
    end,
  },
}
