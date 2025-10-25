vim.api.nvim_create_autocmd("User", {
  pattern = "MiniFilesActionRename",
  callback = function(event)
    Snacks.rename.on_rename_file(event.data.from, event.data.to)
  end,
})
-- needed for image to know in kitty
vim.env.TERM = "exterm-kitty"

vim.api.nvim_create_user_command("Zen", function()
  Snacks.zen()
end, { desc = "Zen" })

local dimmed = false
vim.api.nvim_create_user_command("Dim", function()
  if not dimmed then
    Snacks.dim.enable()
  else
    Snacks.dim.disable()
  end
  dimmed = not dimmed
end, { desc = "Dim" })

---@type table<number, {token:lsp.ProgressToken, msg:string, done:boolean}[]>
local progress = vim.defaulttable()
vim.api.nvim_create_autocmd("LspProgress", {
  ---@param ev {data: {client_id: integer, params: lsp.ProgressParams}}
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    local value = ev.data.params.value --[[@as {percentage?: number, title?: string, message?: string, kind: "begin" | "report" | "end"}]]
    if not client or type(value) ~= "table" then
      return
    end
    local p = progress[client.id]

    for i = 1, #p + 1 do
      if i == #p + 1 or p[i].token == ev.data.params.token then
        p[i] = {
          token = ev.data.params.token,
          msg = ("[%3d%%] %s%s"):format(
            value.kind == "end" and 100 or value.percentage or 100,
            value.title or "",
            value.message and (" **%s**"):format(value.message) or ""
          ),
          done = value.kind == "end",
        }
        break
      end
    end

    local msg = {} ---@type string[]
    progress[client.id] = vim.tbl_filter(function(v)
      return table.insert(msg, v.msg) or not v.done
    end, p)

    local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    vim.notify(table.concat(msg, "\n"), "info", {
      id = "lsp_progress",
      title = client.name,
      opts = function(notif)
        notif.icon = #progress[client.id] == 0 and " "
          or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
      end,
    })
  end,
})

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@module "snacks"
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    rename = { enabled = true },
    quickfile = { enabled = true },
    zen = { enabled = true },
    dim = { enabled = true },
    notifier = { enabled = true },
    animate = { enabled = true },
    statuscolumn = { enabled = true, left = { "git", "mark" }, right = { "sign", "fold" } },
    input = { enabled = true, b = { completion = true } },
    image = { enabled = true },
    indent = { enabled = true, scope = { hl = "NormalFloat" } },
    scope = { enabled = true },
    bufdelete = { enabled = true },
  },
  keys = {
    -- stylua: ignore start
    --
    { "<leader>bd", function() Snacks.bufdelete.delete() end, desc = "delete current buffer" },
    --
    -- stylua: ignore end
  },
}
