-- Metals v2 for GlobalServices, driven by the repo's gs-metals project config
-- (tools/ide/metals/sf.json), the same one `sf ws code -c gs-metals` applies to Cursor.
local M = {}

local PROJECT_CONFIG = "tools/ide/metals/sf.json"
local GENERATOR = "tools/ide/metals/generate_mbt.py"
local CLASSPATH = ".metals/mbt.json"
local STAMP = ".metals/nvim-classpath.json"
local LOCK = ".metals/nvim-owner"
local LOG = ".metals/nvim-classpath.log"
local METALS_MAIN_CLASS = "scala.meta.metals.Main"
local FILETYPES = { "java", "scala", "sbt" }
-- Changes here can change the classpath generate_mbt.py materializes.
local CLASSPATH_INPUTS = {
  ":(glob)**/BUILD",
  ":(glob)**/BUILD.bazel",
  ":(glob)**/*.bzl",
  ":(glob)**/*maven*install*.json",
  "MODULE.bazel",
  "MODULE.bazel.lock",
  "WORKSPACE",
  "tools/ide/metals",
}
-- VS Code setting names that differ from nvim-metals.
local SETTING_ALIASES = { autoImportBuilds = "autoImportBuild" }

local roots = {}
local self_pid = vim.fn.getpid()

local function state(root)
  roots[root] = roots[root] or { warned = {} }
  return roots[root]
end

local function warn_once(root, key, message, level)
  local s = state(root)
  if s.warned[key] then
    return
  end
  s.warned[key] = true
  vim.notify(message, level or vim.log.levels.WARN, { title = "GS Metals" })
end

local function set_status(text)
  vim.g.gs_metals_status = text
  vim.cmd.redrawstatus()
end

local function directory_of(path)
  local dir = vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p")
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return (dir:gsub("/$", ""))
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function write_file(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

--- Snowflake checkout (main repo or worktree) that carries the gs-metals project config.
--- @param start string|nil
--- @return string|nil
function M.root(start)
  local dir = directory_of(start)
  for _ = 1, 40 do
    if vim.fn.filereadable(dir .. "/" .. PROJECT_CONFIG) == 1 then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

local function buffer_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or not vim.tbl_contains(FILETYPES, vim.bo[bufnr].filetype) then
    return nil
  end
  return M.root(name)
end

--- Server settings and JDK version from the project config's codium section.
local function read_project(root)
  local ok, decoded = pcall(vim.json.decode, read_file(root .. "/" .. PROJECT_CONFIG) or "")
  local codium = ok and type(decoded) == "table" and vim.tbl_get(decoded, "ide_configs", "codium")
  if type(codium) ~= "table" then
    return nil, "could not read ide_configs.codium from " .. PROJECT_CONFIG
  end
  local valid = require("metals.config").valid_metals_settings
  local settings = {}
  local java_version
  for _, section in ipairs({ codium.remote_settings or {}, codium.workspace_settings or {} }) do
    for key, value in pairs(section) do
      local name = key:match("^metals%.(.+)$")
      if name then
        name = SETTING_ALIASES[name] or name
        if name == "javaVersion" then
          java_version = tostring(value)
        elseif name == "serverVersion" or vim.tbl_contains(valid, name) then
          settings[name] = value
        end
      end
    end
  end
  if not settings.serverVersion then
    return nil, PROJECT_CONFIG .. " does not set metals.serverVersion"
  end
  if settings.customProjectRoot then
    settings.customProjectRoot = root .. "/" .. settings.customProjectRoot
  end
  return { settings = settings, java_version = java_version or "21" }
end

local function java_major(home)
  if not home or home == "" or vim.fn.executable(home .. "/bin/java") ~= 1 then
    return nil
  end
  local result = vim.system({ home .. "/bin/java", "-version" }, { text = true }):wait()
  return ((result.stderr or "") .. (result.stdout or "")):match("version \"(%d+)")
end

local jdks = {}
local function find_jdk(major)
  if jdks[major] == nil then
    jdks[major] = false
    for _, home in ipairs({
      vim.env.JAVA_HOME,
      "/usr/lib/jvm/temurin-" .. major .. "-jdk",
      "/usr/lib/jvm/java-" .. major .. "-temurin-jdk",
    }) do
      if java_major(home) == major then
        jdks[major] = home
        break
      end
    end
  end
  return jdks[major] or nil
end

local function metals_binary(version)
  return vim.fn.stdpath("cache") .. "/gs-metals/metals-" .. version
end

--- Installs the pinned server once per version, mirroring nvim-metals' coursier bootstrap.
local function install(version, jdk, callback)
  local binary = metals_binary(version)
  if vim.fn.executable(binary) == 1 then
    return callback(true)
  end
  local coursier = (vim.fn.executable("cs") == 1 and "cs") or (vim.fn.executable("coursier") == 1 and "coursier")
  if not coursier then
    return callback(false, "Coursier (`cs`) is not on PATH; it is needed to install Metals " .. version)
  end
  vim.fn.mkdir(vim.fn.fnamemodify(binary, ":h"), "p")
  set_status("installing Metals " .. version)
  vim.system({
    coursier,
    "bootstrap",
    "--java-opt",
    "-Xss4m",
    "--java-opt",
    "-Xms100m",
    "org.scalameta:metals_2.13:" .. version,
    "-r",
    "https://central.sonatype.com/repository/maven-snapshots/",
    "-o",
    binary,
    "-f",
  }, { text = true, env = { JAVA_HOME = jdk } }, function(result)
    vim.schedule(function()
      set_status("")
      if result.code == 0 then
        callback(true)
      else
        callback(false, "Metals " .. version .. " install failed:\n" .. (result.stderr or ""))
      end
    end)
  end)
end

--- missing: no classpath yet. stale: classpath inputs changed since it was generated. fresh: neither.
local function classpath_state(root, callback)
  if vim.fn.filereadable(root .. "/" .. CLASSPATH) == 0 then
    return callback("missing")
  end
  local ok, stamp = pcall(vim.json.decode, read_file(root .. "/" .. STAMP) or "")
  if not ok or type(stamp) ~= "table" or type(stamp.commit) ~= "string" then
    return callback("stale")
  end
  local cmd = { "git", "-C", root, "diff", "--name-only", stamp.commit, "--" }
  vim.list_extend(cmd, CLASSPATH_INPUTS)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      callback((result.code == 0 and vim.trim(result.stdout or "") == "") and "fresh" or "stale")
    end)
  end)
end

local function process_info(pid)
  local status = read_file("/proc/" .. pid .. "/status")
  if not status then
    return nil
  end
  return {
    name = status:match("Name:%s*(%S+)"),
    ppid = tonumber(status:match("PPid:%s*(%d+)")),
  }
end

--- Another live Neovim that claimed this checkout.
local function owner_pid(root)
  local pid = tonumber(read_file(root .. "/" .. LOCK) or "")
  if not pid or pid == self_pid then
    return nil
  end
  local info = process_info(pid)
  return info and info.name == "nvim" and pid or nil
end

--- A Metals server some other editor (for example Cursor) runs on this checkout's .metals.
--- Orphans (parent exited) do not count; generate_mbt.py stops those.
local function foreign_metals(root)
  local prefix = root .. "/.metals/"
  local proc = vim.uv.fs_scandir("/proc")
  while proc do
    local pid = vim.uv.fs_scandir_next(proc)
    if not pid then
      break
    end
    if pid:match("^%d+$") then
      local cmdline = read_file("/proc/" .. pid .. "/cmdline")
      if cmdline and cmdline:find(METALS_MAIN_CLASS, 1, true) then
        local info = process_info(pid)
        if info and info.ppid ~= self_pid and info.ppid ~= 1 then
          local fds = vim.uv.fs_scandir("/proc/" .. pid .. "/fd")
          while fds do
            local fd = vim.uv.fs_scandir_next(fds)
            if not fd then
              break
            end
            local target = vim.uv.fs_readlink("/proc/" .. pid .. "/fd/" .. fd)
            if target and target:sub(1, #prefix) == prefix then
              return tonumber(pid)
            end
          end
        end
      end
    end
  end
end

--- One Metals server per checkout: claim it unless another editor already serves it.
local function claim(root)
  local s = state(root)
  if s.owned then
    return true
  end
  local other = owner_pid(root)
  if other then
    warn_once(
      root,
      "owner",
      "Metals for " .. root .. " already runs in Neovim (pid " .. other .. "); not starting another."
    )
    return false
  end
  local foreign = foreign_metals(root)
  if foreign then
    warn_once(
      root,
      "foreign",
      "Another editor runs Metals for " .. root .. " (pid " .. foreign .. "); not starting another."
    )
    return false
  end
  write_file(root .. "/" .. LOCK, tostring(self_pid))
  s.owned = true
  return true
end

local function release_all()
  for root, s in pairs(roots) do
    if s.owned and tonumber(read_file(root .. "/" .. LOCK) or "") == self_pid then
      os.remove(root .. "/" .. LOCK)
    end
  end
end

local function server_config(root)
  local s = state(root)
  local metals_config = require("metals").bare_config()
  metals_config.settings = vim.tbl_extend("force", vim.deepcopy(s.project.settings), {
    metalsBinaryPath = metals_binary(s.project.settings.serverVersion),
    javaHome = s.jdk,
  })
  metals_config.cmd_env = { JAVA_HOME = s.jdk }
  metals_config.init_options.statusBarProvider = "on"
  metals_config.find_root_dir = function()
    return root
  end
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.get_lsp_capabilities then
    metals_config.capabilities = blink.get_lsp_capabilities()
  end
  return metals_config
end

local function attach(bufnr, root)
  vim.api.nvim_buf_call(bufnr, function()
    require("metals").initialize_or_attach(server_config(root))
  end)
end

local function attach_all(root)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and buffer_root(bufnr) == root then
      attach(bufnr, root)
    end
  end
end

local function start_server(root)
  state(root).running = true
  attach_all(root)
end

--- Metals reads .metals/mbt.json only at startup.
local function restart_server(root)
  local clients = vim.tbl_filter(function(client)
    return client.root_dir == root
  end, vim.lsp.get_clients({ name = "metals" }))
  if #clients == 0 then
    return start_server(root)
  end
  for _, client in ipairs(clients) do
    client:stop(10000)
  end
  local waited = 0
  local function wait()
    for _, client in ipairs(clients) do
      if vim.lsp.get_client_by_id(client.id) then
        waited = waited + 250
        if waited > 15000 then
          vim.notify(
            "Metals did not stop; run :MetalsInfo to inspect it.",
            vim.log.levels.ERROR,
            { title = "GS Metals" }
          )
          return
        end
        return vim.defer_fn(wait, 250)
      end
    end
    start_server(root)
  end
  wait()
end

local function generate(root, on_done)
  local s = state(root)
  if s.generating then
    vim.notify("GS classpath is already generating.", vim.log.levels.INFO, { title = "GS Metals" })
    return
  end
  local head = vim.system({ "git", "-C", root, "rev-parse", "HEAD" }, { text = true }):wait()
  local commit = head.code == 0 and vim.trim(head.stdout) or nil
  local log_path = root .. "/" .. LOG
  vim.fn.mkdir(root .. "/.metals", "p")
  local log = assert(io.open(log_path, "w"))
  local function append(_, data)
    if data then
      log:write(data)
    end
  end

  s.generating = true
  local started = vim.uv.now()
  local timer = assert(vim.uv.new_timer())
  timer:start(
    0,
    1000,
    vim.schedule_wrap(function()
      local seconds = math.floor((vim.uv.now() - started) / 1000)
      set_status(string.format("GS classpath %d:%02d", math.floor(seconds / 60), seconds % 60))
    end)
  )

  vim.system({ root .. "/" .. GENERATOR }, { cwd = root, stdout = append, stderr = append }, function(result)
    log:close()
    vim.schedule(function()
      timer:stop()
      timer:close()
      s.generating = false
      set_status("")
      if result.code == 0 then
        if commit then
          write_file(root .. "/" .. STAMP, vim.json.encode({ commit = commit }))
        end
        vim.notify("GS classpath updated.", vim.log.levels.INFO, { title = "GS Metals" })
        on_done(true)
      else
        vim.notify(
          "generate_mbt.py exited " .. result.code .. "; see " .. log_path,
          vim.log.levels.ERROR,
          { title = "GS Metals" }
        )
        on_done(false)
      end
    end)
  end)
end

local function after_generate(root)
  return function(ok)
    if not ok then
      return
    end
    if state(root).running then
      restart_server(root)
    else
      start_server(root)
    end
  end
end

--- Resolves the project config, JDK, and server once per checkout and session.
local function prepare(root, callback)
  local s = state(root)
  if s.prepared then
    return callback(true)
  end
  local project, err = read_project(root)
  if not project then
    return callback(false, err)
  end
  local jdk = find_jdk(project.java_version)
  if not jdk then
    return callback(false, "Metals needs JDK " .. project.java_version .. "; set JAVA_HOME to one.")
  end
  install(project.settings.serverVersion, jdk, function(ok, install_err)
    if ok then
      s.project, s.jdk, s.prepared = project, jdk, true
    end
    callback(ok, install_err)
  end)
end

--- First Java buffer in a checkout: start Metals now if a classpath exists (refreshing it in the
--- background when stale); otherwise generate it first, because Metals 2.0.0-RC1 starts a Scala CLI
--- build server that never finishes connecting when .metals/mbt.json is missing.
local function activate(root)
  local s = state(root)
  if s.activating or not claim(root) then
    return
  end
  s.activating = true
  prepare(root, function(ok, err)
    if not ok then
      s.activating = false
      return warn_once(root, "prepare", err, vim.log.levels.ERROR)
    end
    classpath_state(root, function(status)
      if status == "missing" then
        vim.notify(
          "Generating the GS classpath before starting Metals (first run takes a few minutes).",
          vim.log.levels.INFO,
          { title = "GS Metals" }
        )
        generate(root, after_generate(root))
      else
        start_server(root)
        if status == "stale" then
          generate(root, after_generate(root))
        end
      end
    end)
  end)
end

function M.on_buffer(bufnr)
  local root = buffer_root(bufnr)
  if not root then
    return
  end
  if state(root).running then
    attach(bufnr, root)
  else
    activate(root)
  end
end

function M.refresh_classpath()
  local root = M.root(vim.api.nvim_buf_get_name(0)) or M.root(vim.fn.getcwd())
  if not root then
    vim.notify("Not inside a snowflake checkout (no " .. PROJECT_CONFIG .. ").", vim.log.levels.ERROR)
    return
  end
  state(root).warned = {}
  if not claim(root) then
    return
  end
  prepare(root, function(ok, err)
    if not ok then
      return vim.notify(err, vim.log.levels.ERROR, { title = "GS Metals" })
    end
    generate(root, after_generate(root))
  end)
end

function M.status()
  local status = vim.g.gs_metals_status
  if status and status ~= "" then
    return status
  end
  status = vim.g.metals_status or ""
  if #status > 48 then
    return status:sub(1, 45) .. "..."
  end
  return status
end

function M.setup()
  vim.api.nvim_create_user_command("GsMetalsClasspath", M.refresh_classpath, {
    desc = "Regenerate the GlobalServices classpath and restart Metals",
  })
  local group = vim.api.nvim_create_augroup("kaleb-gs-metals", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = FILETYPES,
    group = group,
    callback = function(args)
      M.on_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = release_all })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.on_buffer(bufnr)
    end
  end
end

return M
