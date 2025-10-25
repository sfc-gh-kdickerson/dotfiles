M = {}

-- Function to get the Python interpreter from the active virtual environment
M.get_python_path = function()
  -- First, check if VIRTUAL_ENV is set
  local venv = os.getenv("VIRTUAL_ENV")
  if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
    print(venv .. "/bin/python")
    return venv .. "/bin/python"
  end

  -- If using Poetry, find the Poetry virtual environment
  if vim.fn.executable("poetry") == 1 then
    local poetry_env = vim.fn.systemlist("poetry env info -p")[1]
    if poetry_env and vim.fn.isdirectory(poetry_env) == 1 then
      return poetry_env .. "/bin/python"
    end
  end

  -- Fallback to default Python
  return vim.fn.exepath("python3") or vim.fn.exepath("python")
end

M.python_venv = function()
  local venv = vim.env.VIRTUAL_ENV -- or vim.env.CONDA_DEFAULT_ENV
  if venv then
    return string.format("🐍 %s", vim.fn.fnamemodify(venv, ":h:t"))
  else
    return ""
  end
end

return M
