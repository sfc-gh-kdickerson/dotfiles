-- only should be used when passed from CLI like 'nvim -c PodLogs mypod json'
vim.api.nvim_create_user_command("PodLogs", function(opts)
  local pod_name, pod_namespace, pod_context, file_type = unpack(opts.fargs)
  if file_type == nil then
    file_type = "json"
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, pod_name .. " logs")
  vim.api.nvim_set_option_value("filetype", file_type, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_current_buf(buf)
  local cmd = { "kubectl", "logs", "-f", pod_name, "-n", pod_namespace, "--context", pod_context }
  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if data then
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
        vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
      end
    end,
    on_exit = function()
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "-- Stream ended --" })
    end,
  })
end, { nargs = "*" })

vim.api.nvim_create_user_command("MarkdownToPDF", function(opts)
  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t:r")
  local output_pdf = filename .. ".pdf"

  -- Ensure the current file is a Markdown file
  if vim.bo.filetype ~= "markdown" then
    vim.notify("This command can only be run on Markdown files!", vim.log.levels.ERROR)
    return
  end

  -- Build the Pandoc command
  local command = string.format(
    "pandoc --from=gfm --to=pdf %s -o %s --pdf-engine=lualatex -V geometry:margin=0.2in -V tables=yes -V longtable",
    vim.fn.shellescape(filepath),
    vim.fn.shellescape(output_pdf)
  )

  -- Run the Pandoc command
  local result = vim.fn.system(command)

  -- Handle success or failure
  if vim.v.shell_error == 0 then
    vim.notify("Successfully converted to PDF: " .. output_pdf, vim.log.levels.INFO)
  else
    vim.notify("Error converting to PDF:\n" .. result, vim.log.levels.ERROR)
  end
end, { nargs = 0 })

vim.api.nvim_create_user_command("NewSession", function()
  local nvim_dir = vim.fn.getcwd() .. "/.nvim"
  local stat = vim.loop.fs_stat(nvim_dir)
  if not stat then
    vim.fn.mkdir(nvim_dir)
  else
  end
  vim.cmd("mksession " .. nvim_dir .. "/default_session.vim")
end, { desc = "Creates new session in .nvim directory from cwd" })

vim.api.nvim_create_user_command("Git", function()
  -- require("neogit").open({kind = "replace"})
  require("neogit").open()
  local current_buf = vim.api.nvim_get_current_buf()
  local bufs = vim.api.nvim_list_bufs()
  for _, buf in ipairs(bufs) do
    if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
      pcall(function()
        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end
  end
  vim.keymap.set('n', 'q', ':quit<CR>', { buffer = current_buf, desc = 'Quit dedicated neogit buffer' })
  vim.keymap.set('n', '<C-g>', ':quit<CR>', { buffer = current_buf, desc = 'Quit dedicated neogit buffer' })
end, { desc = "Opens Neogit immediately" })

