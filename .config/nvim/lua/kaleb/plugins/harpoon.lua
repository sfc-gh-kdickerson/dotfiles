return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup()

      vim.keymap.set("n", "<leader>ha", function()
        local filename = vim.fn.expand("%:p")
        local new_file_index = harpoon:list():length() + 1
        vim.notify(
          "Adding " .. filename .. " to harpoon at index " .. new_file_index,
          vim.log.levels.INFO,
          { title = "Harpoon" }
        )
        harpoon:list():add()
      end, { desc = "Add File to Harpoon" })

      vim.keymap.set("n", "<leader>he", function()
        local filename = vim.fn.expand("%:p")
        vim.notify("Erasing " .. filename .. " from harpoon", vim.log.levels.INFO, { title = "Harpoon" })
        harpoon:list():remove()
      end, { desc = "Erase File From Harpoon" })

      vim.keymap.set("n", "<leader>hh", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = "Toggle Harpoon Menu" })

      vim.keymap.set("n", "<leader>1", function()
        harpoon:list():select(1)
      end, { desc = "Harpoon 1" })
      vim.keymap.set("n", "<leader>2", function()
        harpoon:list():select(2)
      end, { desc = "Harpoon 2" })
      vim.keymap.set("n", "<leader>3", function()
        harpoon:list():select(3)
      end, { desc = "Harpoon 3" })
      vim.keymap.set("n", "<leader>4", function()
        harpoon:list():select(4)
      end, { desc = "Harpoon 4" })
      vim.keymap.set("n", "<leader>5", function()
        harpoon:list():select(5)
      end, { desc = "Harpoon 5" })

      -- -- Toggle previous & next buffers stored within Harpoon list
      -- vim.keymap.set("n", "<C-p>", function()
      --   harpoon:list():prev()
      -- end)
      -- vim.keymap.set("n", "<C-n>", function()
      --   harpoon:list():next()
      -- end)
    end,
  },
}
