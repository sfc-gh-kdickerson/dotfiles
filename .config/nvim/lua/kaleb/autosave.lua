local filetypes = { "*.rs" }
local debounce_ms = 500

local autosaving = false

---@diagnostic disable-next-line: undefined-field
local timer = vim.loop.new_timer()
local autosave_group = vim.api.nvim_create_augroup("AutoSave", { clear = true })
vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
  group = autosave_group,
  pattern = filetypes,
  callback = function()
    timer:stop()
    timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        local mode = vim.api.nvim_get_mode().mode
        if vim.bo.modified and not mode:find("[iIrRsS]") then
          vim.notify("Auto-saving file...", vim.log.levels.INFO, { title = "AutoSave" })
          autosaving = true
          vim.cmd("silent update")
          autosaving = false
        end
      end)
    )
  end,
})

local manual_save_reminder_group = vim.api.nvim_create_augroup("ManualSaveReminder", { clear = true })
vim.api.nvim_create_autocmd("BufWritePost", {
  group = manual_save_reminder_group,
  pattern = filetypes,
  callback = function()
    if not autosaving then
      vim.notify(
        "Auto-save enabled for this file. No need to save manually!",
        vim.log.levels.WARN,
        { title = "Manual Save" }
      )
    end
  end,
})
