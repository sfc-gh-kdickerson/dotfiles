return {
  "CRAG666/code_runner.nvim",
  cmd = { "RunCode", "RunFile", "RunProject", "RunClose", "CRFiletype", "CRProjects" },
  keys = {
    { "<leader>ru", function() require("code_runner").run_filetype() end, desc = "Run File" },
  },
  opts = {
    mode = "term",
    focus = false,
    filetype = {
      cpp = {
        "cd $dir &&",
        "clang++ $fileName -o /tmp/$fileNameWithoutExt &&",
        "/tmp/$fileNameWithoutExt",
      },
      rust = function()
        local file = vim.fn.expand("%:p")
        local bin = vim.fn.expand("%:t:r")
        local root = "/Users/kaleb/Projects/project-euler"

        if file:match("/project%-euler/solutions/src/bin/.+%.rs$") then
          return ("cd %s && RUSTFLAGS='-Awarnings' cargo run --quiet -p solutions --release --bin %s")
            :format(vim.fn.shellescape(root), vim.fn.shellescape(bin))
        end

        local dir = vim.fn.expand("%:p:h")
        return ("cd %s && rustc -Awarnings %s -o /tmp/%s && /tmp/%s")
          :format(
            vim.fn.shellescape(dir),
            vim.fn.shellescape(file),
            vim.fn.shellescape(bin),
            vim.fn.shellescape(bin)
          )
      end,
    },
  },
}
