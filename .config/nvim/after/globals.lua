-- M = {}

P = function(table)
  print(vim.inspect(table))
  return table
end

R = function(name)
  require("plenary.reload").reload_module(name)
end

-- return M
