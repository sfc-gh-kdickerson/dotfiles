return {
  -- { "echasnovski/mini.notify", version = "*", opts = {} },
  -- { "echasnovski/mini.trailspace", version = "*", opts = {} },
  -- { "echasnovski/mini.jump", version = "*", opts = { delay = { highlight = 10 ^ 7, } } },
  -- { "echasnovski/mini.indentscope", version = "*", event = "VeryLazy", opts = { symbol = "│" } },
  -- { "echasnovski/mini.jump2d", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.ai", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.surround", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.bracketed", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.comment", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.cursorword", version = "*", event = "VeryLazy", opts = {} },
  { "echasnovski/mini.icons", version = "*", event = "VeryLazy", opts = {} },
  -- {
  --   "echasnovski/mini.sessions",
  --   version = "*",
  --   priority = 1000,
  --   opts = {
  --     autoread = true,
  --     directory = "",
  --     file = ".nvim/default_session.vim",
  --     hooks = {
  --       post = {
  --         -- needed because lsp is loaded after bufopen event is fired
  --         read = function()
  --           vim.defer_fn(function()
  --             vim.cmd("LspStart")
  --           end, 1000)
  --         end,
  --       },
  --     },
  --   },
  -- },
  {
    "echasnovski/mini.pairs",
    enabled = true,
    event = { "VeryLazy" },
    version = "*",
    opts = {
      -- In which modes mappings from this `config` should be created
      modes = { insert = true, command = false, terminal = false },

      -- Global mappings. Each right hand side should be a pair information, a
      -- table with at least these fields (see more in |MiniPairs.map|):
      -- - <action> - one of 'open', 'close', 'closeopen'.
      -- - <pair> - two character string for pair to be used.
      -- By default pair is not inserted after `\`, quotes are not recognized by
      -- `<CR>`, `'` does not insert pair after a letter.
      -- Only parts of tables can be tweaked (others will use these defaults).
      mappings = {
        [")"] = { action = "close", pair = "()", neigh_pattern = "[^\\]." },
        ["]"] = { action = "close", pair = "[]", neigh_pattern = "[^\\]." },
        ["}"] = { action = "close", pair = "{}", neigh_pattern = "[^\\]." },
        ["["] = {
          action = "open",
          pair = "[]",
          neigh_pattern = ".[%s%z%)}%]]",
          register = { cr = false },
          -- foo|bar -> press "[" -> foo[bar
          -- foobar| -> press "[" -> foobar[]
          -- |foobar -> press "[" -> [foobar
          -- | foobar -> press "[" -> [] foobar
          -- foobar | -> press "[" -> foobar []
          -- {|} -> press "[" -> {[]}
          -- (|) -> press "[" -> ([])
          -- [|] -> press "[" -> [[]]
        },
        ["{"] = {
          action = "open",
          pair = "{}",
          -- neigh_pattern = ".[%s%z%)}]",
          neigh_pattern = ".[%s%z%)}%]]",
          register = { cr = false },
          -- foo|bar -> press "{" -> foo{bar
          -- foobar| -> press "{" -> foobar{}
          -- |foobar -> press "{" -> {foobar
          -- | foobar -> press "{" -> {} foobar
          -- foobar | -> press "{" -> foobar {}
          -- (|) -> press "{" -> ({})
          -- {|} -> press "{" -> {{}}
        },
        ["("] = {
          action = "open",
          pair = "()",
          -- neigh_pattern = ".[%s%z]",
          neigh_pattern = ".[%s%z%)]",
          register = { cr = false },
          -- foo|bar -> press "(" -> foo(bar
          -- foobar| -> press "(" -> foobar()
          -- |foobar -> press "(" -> (foobar
          -- | foobar -> press "(" -> () foobar
          -- foobar | -> press "(" -> foobar ()
        },
        -- Single quote: Prevent pairing if either side is a letter
        ["\""] = {
          action = "closeopen",
          pair = "\"\"",
          neigh_pattern = "[^%w\\][^%w]",
          register = { cr = false },
        },
        -- Single quote: Prevent pairing if either side is a letter
        ["'"] = {
          action = "closeopen",
          pair = "''",
          neigh_pattern = "[^%w\\][^%w]",
          register = { cr = false },
        },
        -- Backtick: Prevent pairing if either side is a letter
        ["`"] = {
          action = "closeopen",
          pair = "``",
          neigh_pattern = "[^%w\\][^%w]",
          register = { cr = false },
        },
      },
    },
  },
  {
    "echasnovski/mini.clue",
    version = "*",
    event = "VeryLazy",
    config = function()
      local miniclue = require("mini.clue")
      miniclue.setup({
        triggers = {
          -- Leader triggers
          { mode = "n", keys = "<Leader>" },
          -- Built-in completion
          { mode = "i", keys = "<C-x>" },
          -- keys
          { mode = "n", keys = "g" },
          { mode = "n", keys = "T" },
          { mode = "n", keys = "<leader>f" },
          { mode = "n", keys = "<leader>s" },
          { mode = "n", keys = "<leader>h" },
          { mode = "n", keys = "<leader>d" },
          { mode = "n", keys = "z" },
          { mode = "n", keys = "[" },
          { mode = "n", keys = "]" },
          -- Marks
          { mode = "n", keys = "'" },
          { mode = "n", keys = "`" },
          -- Registers
          { mode = "n", keys = "\"" },
          { mode = "i", keys = "<C-r>" },
          { mode = "c", keys = "<C-r>" },
          -- Window commands
          { mode = "n", keys = "<C-w>" },
        },

        clues = {
          -- Enhance this by adding descriptions for <Leader> mapping groups
          miniclue.gen_clues.builtin_completion(),
          miniclue.gen_clues.g(),
          miniclue.gen_clues.marks(),
          miniclue.gen_clues.registers(),
          miniclue.gen_clues.windows(),
          miniclue.gen_clues.z(),
        },
        window = {
          config = {
            width = "auto",
          },
        },
      })
    end,
  },
  {
    "echasnovski/mini.hipatterns",
    version = "*",
    event = "VeryLazy",
    config = function()
      local hipatterns = require("mini.hipatterns")
      hipatterns.setup({
        highlighters = {
          fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
          hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
          todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsTodo" },
          note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },
          hex_color = hipatterns.gen_highlighter.hex_color(),
        },
      })
    end,
  },
  {
    "echasnovski/mini.files",
    version = "*",
    config = function()
      local minifiles = require("mini.files")
      minifiles.setup({
        options = {
          use_as_default_explorer = false,
        },
        mappings = {
          go_in_plus = "<CR>",
        },
      })
      vim.keymap.set("n", "<leader>tf", function()
        minifiles.open(vim.api.nvim_buf_get_name(0))
      end)
      vim.keymap.set("n", "<leader>tt", minifiles.open)
    end,
  },
}
