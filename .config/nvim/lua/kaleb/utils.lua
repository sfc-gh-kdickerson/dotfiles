M = {}

M.get_python_path = function()
  -- 1. Check if VIRTUAL_ENV is set (standard venv)
  local venv = os.getenv("VIRTUAL_ENV")
  if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
    vim.notify("Found standard venv: " .. venv .. "/bin/python")
    return venv .. "/bin/python"
  end

  -- 2. Check if CONDA_PREFIX is set (Conda environment)
  local conda_prefix = os.getenv("CONDA_PREFIX")
  if conda_prefix and vim.fn.executable(conda_prefix .. "/bin/python") == 1 then
    vim.notify("Found Conda env: " .. conda_prefix .. "/bin/python")
    return conda_prefix .. "/bin/python"
  end

  -- 3. If using Poetry, find the Poetry virtual environment
  if vim.fn.executable("poetry") == 1 then
    -- Using vim.fn.systemlist for better handling of multi-line output
    local poetry_env_info = vim.fn.systemlist("poetry env info -p")
    local poetry_env = poetry_env_info[1]
    if poetry_env and vim.fn.isdirectory(poetry_env) == 1 then
      vim.notify("Found Poetry env: " .. poetry_env .. "/bin/python")
      return poetry_env .. "/bin/python"
    end
  end

  -- 4. Fallback to default Python
  return vim.fn.exepath("python3") or vim.fn.exepath("python")
end

---

M.python_venv = function()
  local venv = vim.env.VIRTUAL_ENV
  local conda_env = vim.env.CONDA_DEFAULT_ENV

  -- Prioritize Conda environment name if set
  if conda_env and conda_env ~= "base" then
    -- Conda environment names are typically just the name, not a full path
    return string.format("🐍 (Conda) %s", conda_env)
  elseif venv then
    -- Use the name of the standard virtual environment directory
    return string.format("🐍 %s", vim.fn.fnamemodify(venv, ":h:t"))
  else
    return ""
  end
end

return M
