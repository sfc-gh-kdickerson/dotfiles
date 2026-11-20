M = {}

local announced = {}

local function announce(message)
  if announced[message] then
    return
  end
  announced[message] = true
  vim.notify(message)
end

local function directory_of(path)
  local dir = vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p")
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return (dir:gsub("/$", ""))
end

local function walk_parents(start, visit)
  local dir = directory_of(start)
  for _ = 1, 40 do
    if visit(dir) then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
  return nil
end

local function is_git_root(dir)
  local git = dir .. "/.git"
  return vim.fn.isdirectory(git) == 1 or vim.fn.filereadable(git) == 1
end

-- bazel-bin points at <output_base>/execroot/_main/bazel-out/<config>/bin.
-- The repo conda env lives in <output_base>/external, not on PATH.
local function bazel_conda_python(start)
  local found
  walk_parents(start, function(dir)
    local link = dir .. "/bazel-bin"
    if vim.fn.getftype(link) ~= "link" then
      return false
    end
    local output_base = vim.fn.fnamemodify(vim.fn.resolve(link), ":h:h:h:h:h")
    local external = output_base .. "/external"
    if vim.fn.isdirectory(external) == 0 then
      return false
    end
    for _, name in ipairs(vim.fn.readdir(external)) do
      if name:find("conda_env", 1, true) then
        local python = external .. "/" .. name .. "/env/bin/python"
        if vim.fn.executable(python) == 1 then
          found = python
          return true
        end
      end
    end
    return false
  end)
  return found
end

local function build_import_paths(dir, git_root)
  local paths = {}
  for _, name in ipairs({ "BUILD.bazel", "BUILD" }) do
    local build_file = dir .. "/" .. name
    if vim.fn.filereadable(build_file) == 1 then
      local text = table.concat(vim.fn.readfile(build_file), "\n")
      for body in text:gmatch("imports%s*=%s*%[([^%]]*)%]") do
        for rel in body:gmatch("[\"']([^\"']+)[\"']") do
          if rel ~= "." and rel ~= "" then
            local imported = vim.fn.fnamemodify(dir .. "/" .. rel, ":p"):gsub("/$", "")
            if imported:find(git_root .. "/", 1, true) == 1 and vim.fn.isdirectory(imported) == 1 then
              table.insert(paths, imported)
            end
          end
        end
      end
      break
    end
  end
  return paths
end

-- Import roots for a file: each directory from the file up to the git root,
-- Bazel `imports` from BUILD files along that walk, then the git root.
-- The git root is where `snowflake` itself is imported from.
M.python_analysis_paths = function(start)
  start = start or vim.fn.getcwd()
  local git_root = walk_parents(start, is_git_root)
  if not git_root then
    return {}
  end

  local paths = {}
  local seen = {}
  local function add(path)
    path = path:gsub("/$", "")
    if path ~= "" and not seen[path] and (path == git_root or path:find(git_root .. "/", 1, true) == 1) then
      if vim.fn.isdirectory(path) == 1 then
        seen[path] = true
        table.insert(paths, path)
      end
    end
  end

  walk_parents(start, function(dir)
    if dir == git_root then
      return true
    end
    add(dir)
    for _, imported in ipairs(build_import_paths(dir, git_root)) do
      add(imported)
    end
    return false
  end)
  add(git_root)
  return paths
end

M.get_python_path = function(start)
  start = start or vim.fn.getcwd()

  -- 1. Check if VIRTUAL_ENV is set (standard venv)
  local venv = os.getenv("VIRTUAL_ENV")
  if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
    local python = venv .. "/bin/python"
    announce("Found standard venv: " .. python)
    return python
  end

  -- 2. Check if CONDA_PREFIX is set (Conda environment)
  local conda_prefix = os.getenv("CONDA_PREFIX")
  if conda_prefix and vim.fn.executable(conda_prefix .. "/bin/python") == 1 then
    local python = conda_prefix .. "/bin/python"
    announce("Found Conda env: " .. python)
    return python
  end

  -- 3. If using Poetry, find the Poetry virtual environment
  if vim.fn.executable("poetry") == 1 then
    local poetry_env_info = vim.fn.systemlist("poetry env info -p")
    local poetry_env = poetry_env_info[1]
    if poetry_env and vim.fn.isdirectory(poetry_env) == 1 then
      local python = poetry_env .. "/bin/python"
      announce("Found Poetry env: " .. python)
      return python
    end
  end

  -- 4. Bazel conda toolchain, discovered from the bazel-bin symlink.
  local bazel_python = bazel_conda_python(start)
  if bazel_python then
    announce("Found Bazel conda env: " .. bazel_python)
    return bazel_python
  end

  -- 5. Fallback to default Python
  return vim.fn.exepath("python3") or vim.fn.exepath("python")
end

-- Point a pyright client at the interpreter and import roots for start.
-- Returns true when settings changed and the server should be reconfigured.
M.apply_pyright_settings = function(settings, start)
  settings.python = settings.python or {}
  settings.python.analysis = settings.python.analysis or {}
  local changed = false

  local python_path = M.get_python_path(start)
  if python_path and python_path ~= "" and settings.python.pythonPath ~= python_path then
    settings.python.pythonPath = python_path
    changed = true
  end

  local paths = M.python_analysis_paths(start)
  if #paths > 0 then
    local current = settings.python.analysis.extraPaths or {}
    local seen = {}
    for _, path in ipairs(current) do
      seen[path] = true
    end
    local merged = vim.list_extend({}, current)
    local grew = false
    for _, path in ipairs(paths) do
      if not seen[path] then
        seen[path] = true
        grew = true
        table.insert(merged, path)
      end
    end
    if grew or settings.python.analysis.extraPaths == nil then
      settings.python.analysis.extraPaths = merged
      changed = true
    end
  end

  return changed
end

---

M.python_venv = function()
  local venv = vim.env.VIRTUAL_ENV
  local conda_env = vim.env.CONDA_DEFAULT_ENV

  -- Prioritize Conda environment name if set
  if conda_env and conda_env ~= "base" then
    return string.format("(Conda) %s", conda_env)
  elseif venv then
    -- Basename of the virtualenv directory (VIRTUAL_ENV points at the root)
    return vim.fn.fnamemodify(venv, ":t")
  else
    return ""
  end
end

return M
