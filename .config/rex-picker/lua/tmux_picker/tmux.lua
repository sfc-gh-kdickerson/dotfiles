-- tmux-picker's tmux module, answered by the Rex server instead. rex-picker puts
-- this directory ahead of tmux-picker's own lua/ so every view and plugin that
-- requires "tmux_picker.tmux" gets these functions.
--
-- Targets keep tmux's shapes so plugins work unchanged: sessions by label, panes
-- as "%<block uuid>" (the Cursor hook writes agent state under the same key),
-- windows as Rex window IDs or "session:index".
local config = require("tmux_picker.config")
local json = require("tmux_picker.json")
local util = require("tmux_picker.util")

local M = {}

local rex_bin = util.shell_quote(os.getenv("REX_PICKER_REX") or "rex")
local state_script = os.getenv("REX_PICKER_STATE")
	or ((os.getenv("XDG_CONFIG_HOME") or (config.home .. "/.config")) .. "/rex-picker/state.lua")

-- Keep picker runtime files apart from tmux-picker's, which may be open in tmux.
local runtime = config.runtime_dir .. "/rex-picker"
os.execute("mkdir -p " .. util.shell_quote(runtime))
config.runtime_dir = runtime
config.prompt_file = runtime .. "/prompt"
config.view_file = runtime .. "/view"
config.tmux_sock_file = runtime .. "/sock"
local mru_file = runtime .. "/mru.json"
local error_file = runtime .. "/notify.log"

function util.notify(message)
	message = "rex-picker: " .. tostring(message)
	local log = io.open(error_file, "a")
	if log then
		log:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
		log:close()
	end
	local tty = io.open("/dev/tty", "w")
	if tty then
		tty:write("\27]9;", (message:gsub("[%c]", " ")), "\7")
		tty:close()
	end
end

local function rex(arguments)
	return util.run(rex_bin .. " --autostart=false " .. arguments .. " 2>/dev/null")
end

local function rex_ok(arguments)
	local ok = os.execute(rex_bin .. " --autostart=false " .. arguments .. " >/dev/null 2>&1")
	return ok == true or ok == 0
end

local function pane_target(block_id)
	return "%" .. (tostring(block_id):gsub("^block:", ""))
end

local function block_id(target)
	return "block:" .. (tostring(target or ""):gsub("^%%", ""))
end

-- Popups opened by init.lua (scratch shell, lazygit, this picker) are not panes.
local function listed(block)
	return not tostring(block.label or ""):match("^rex%-")
end

local state

local function read_mru()
	local data = json.read(mru_file)
	return type(data) == "table" and data or {}
end

local function load()
	if state then
		return state
	end
	local output = rex("do " .. util.shell_quote(state_script))
	local ok, decoded = pcall(json.decode, output or "")
	state = ok and type(decoded) == "table" and decoded or {}
	state.sessions = state.sessions or {}
	state.clients = state.clients or {}
	state.by_label, state.by_id, state.windows, state.panes = {}, {}, {}, {}
	local attached = {}
	for _, client in ipairs(state.clients) do
		for _, id in ipairs(client.sessions or {}) do
			attached[id] = (attached[id] or 0) + 1
		end
	end
	local mru = read_mru()
	for _, s in ipairs(state.sessions) do
		s.windows = s.windows or {}
		s.attached = attached[s.id] or 0
		s.last_attached = tonumber(mru[s.label]) or 0
		state.by_label[s.label] = state.by_label[s.label] or s
		state.by_id[s.id] = s
		for _, w in ipairs(s.windows) do
			w.session = s
			w.blocks = w.blocks or {}
			state.windows[w.id] = w
			local index = 0
			for _, b in ipairs(w.blocks) do
				b.window = w
				b.session = s
				if listed(b) then
					index = index + 1
					b.index = index
					state.panes[pane_target(b.id)] = b
				end
			end
		end
	end
	return state
end

local function invalidate()
	state = nil
end

local function find_session(name)
	local current = load()
	return current.by_label[name] or current.by_id[name]
end

local function find_window(target)
	local current = load()
	if current.windows[target] then
		return current.windows[target]
	end
	local session, index = tostring(target or ""):match("^(.*):(%d+)$")
	local s = session and find_session(session)
	return s and s.windows[tonumber(index)] or nil
end

local function focused_block(window)
	for _, b in ipairs(window.blocks) do
		if b.id == window.focused then
			return b
		end
	end
	for _, b in ipairs(window.blocks) do
		if listed(b) then
			return b
		end
	end
end

local function active_window(s)
	for _, w in ipairs(s.windows) do
		if w.id == s.active_window_id then
			return w
		end
	end
	return s.windows[1]
end

local function session_vars(s)
	local window = active_window(s)
	local block = window and focused_block(window)
	return {
		session_name = s.label,
		session_id = s.id,
		session_attached = s.attached,
		session_last_attached = s.last_attached,
		pane_current_path = block and block.cwd or "",
	}
end

local function window_vars(w)
	local vars = session_vars(w.session)
	local block = focused_block(w)
	vars.window_id = w.id
	vars.window_index = w.index
	vars.window_name = w.label or ""
	vars.window_active = w.id == w.session.active_window_id and 1 or 0
	vars.window_zoomed_flag = w.zoomed and 1 or 0
	vars.window_layout = ""
	vars.pane_current_path = block and block.cwd or ""
	vars.pane_current_command = block and block.command or ""
	return vars
end

local function pane_vars(b)
	local vars = window_vars(b.window)
	vars.pane_id = pane_target(b.id)
	vars.pane_index = b.index
	vars.pane_title = b.label or ""
	vars.pane_current_command = b.command or ""
	vars.pane_current_path = b.cwd or ""
	vars.pane_pid = b.pid or ""
	vars.pane_active = b.id == b.window.focused and 1 or 0
	vars.pane_width = ""
	vars.pane_height = ""
	return vars
end

local function expand(format, vars)
	return (format:gsub("#{([%w_]+)}", function(name)
		local value = vars[name]
		return value == nil and "" or util.clean_field(value)
	end))
end

local function app_client()
	local current = load()
	local here = os.getenv("REX_SESSION")
	for _, client in ipairs(current.clients) do
		for _, id in ipairs(client.sessions or {}) do
			if here and (id == here or ("session:" .. here) == id) then
				return client.id
			end
		end
	end
	return current.clients[1] and current.clients[1].id or nil
end

local function select_session(s, window_id)
	local client = app_client()
	if not client then
		util.notify("no Rex app is attached to this server")
		return
	end
	local mru = read_mru()
	mru[s.label] = os.time()
	util.write_file(mru_file, json.encode(mru))
	local arguments = "-C " .. util.shell_quote(client) .. " do session.select session_id=" .. util.shell_quote(s.id)
	if window_id then
		arguments = arguments .. " window_id=" .. util.shell_quote(window_id)
	end
	rex(arguments)
end

function M.command(arguments)
	return "true " .. util.shell_quote(arguments or "")
end

function M.run()
	return nil
end

function M.save_socket() end

function M.has_session(name)
	if not name or name == "" then
		return false
	end
	return find_session(name) ~= nil
end

function M.ensure_session(name, path)
	if M.has_session(name) then
		return
	end
	local arguments = "new " .. util.shell_quote(name)
	if path and path ~= "" then
		arguments = arguments .. " -c " .. util.shell_quote(path)
	end
	rex(arguments .. " --json")
	invalidate()
end

function M.switch_session(name)
	local s = find_session(name)
	if s then
		select_session(s)
	end
end

function M.switch_window(target)
	local w = find_window(target)
	if not w then
		util.die("window " .. tostring(target) .. " is gone")
	end
	select_session(w.session, w.id)
end

function M.switch_pane(target)
	local b = load().panes[target]
	if not b then
		util.die("pane " .. tostring(target) .. " is gone")
	end
	rex("api call -s " .. util.shell_quote(b.session.id) .. " session.focus_block "
		.. util.shell_quote(json.encode({ block_id = b.id })))
	select_session(b.session, b.window.id)
end

function M.kill(kind, target)
	if kind == "session" then
		local s = find_session(target)
		if s then
			rex_ok("kill " .. util.shell_quote(s.id))
		end
	elseif kind == "window" then
		local w = find_window(target)
		if w then
			rex_ok("window close -s " .. util.shell_quote(w.session.id) .. " " .. util.shell_quote(w.id))
		end
	elseif kind == "pane" then
		local b = load().panes[target]
		if b then
			rex_ok("block close -s " .. util.shell_quote(b.session.id) .. " " .. util.shell_quote(b.id))
		end
	end
	invalidate()
end

-- tmux key names used by plugins, in Rex's spelling.
local keys = { Enter = "enter", Escape = "escape", Tab = "tab", BSpace = "backspace", Space = "space" }

local function rex_key(key)
	if keys[key] then
		return keys[key]
	end
	local ctrl = key:match("^C%-(.+)$")
	if ctrl then
		return "ctrl+" .. ctrl:lower()
	end
	local meta = key:match("^M%-(.+)$")
	if meta then
		return "alt+" .. meta:lower()
	end
	return key:lower()
end

function M.send_keys(pane, ...)
	local b = load().panes[pane]
	if not b then
		return false
	end
	local scope = " -s " .. util.shell_quote(b.session.id) .. " -b " .. util.shell_quote(b.id)
	local arguments = { ... }
	local index = 1
	while index <= #arguments do
		local argument = arguments[index]
		local ok
		if argument == "-l" then
			index = index + 1
			ok = rex_ok("send" .. scope .. " -- " .. util.shell_quote(arguments[index] or ""))
		else
			ok = rex_ok("send-key" .. scope .. " " .. util.shell_quote(rex_key(argument)))
		end
		if not ok then
			return false
		end
		index = index + 1
	end
	return true
end

function M.pane_pid(pane)
	local b = load().panes[pane]
	return b and b.pid and tostring(b.pid) or nil
end

function M.pane_owns_pid(pane, pid)
	local owner = M.pane_pid(pane)
	local current = tostring(pid or "")
	if not owner or not current:match("^%d+$") then
		return false
	end
	for _ = 1, 8 do
		if current == owner then
			return true
		end
		local parent = util.run("ps -o ppid= -p " .. util.shell_quote(current) .. " 2>/dev/null")
		current = parent and util.trim(parent) or ""
		if current == "" or current == "1" then
			break
		end
	end
	return false
end

local function sessions_in_order()
	local rows = {}
	for _, s in ipairs(load().sessions) do
		rows[#rows + 1] = s
	end
	return rows
end

function M.list_session_paths()
	local lines = {}
	for _, s in ipairs(sessions_in_order()) do
		lines[#lines + 1] = expand(
			"#{session_name}\t#{pane_current_path}\t#{session_last_attached}\t#{session_attached}",
			session_vars(s)
		)
	end
	return lines
end

local function each_pane(windows, format)
	local lines = {}
	for _, w in ipairs(windows) do
		for _, b in ipairs(w.blocks) do
			if b.index then
				lines[#lines + 1] = expand(format, pane_vars(b))
			end
		end
	end
	return lines
end

local function all_windows()
	local windows = {}
	for _, s in ipairs(sessions_in_order()) do
		for _, w in ipairs(s.windows) do
			windows[#windows + 1] = w
		end
	end
	return windows
end

function M.list_panes(format)
	return each_pane(all_windows(), format)
end

function M.list_windows_all(format)
	local lines = {}
	for _, w in ipairs(all_windows()) do
		lines[#lines + 1] = expand(format, window_vars(w))
	end
	return lines
end

function M.list_windows(session, format)
	local s = find_session(session)
	local lines = {}
	for _, w in ipairs(s and s.windows or {}) do
		lines[#lines + 1] = expand(format, window_vars(w))
	end
	return lines
end

function M.list_window_panes(target, format)
	local w = find_window(target)
	return w and each_pane({ w }, format) or {}
end

function M.info(target, format)
	local b = load().panes[target]
	if b then
		return expand(format, pane_vars(b))
	end
	local w = find_window(target)
	return w and expand(format, window_vars(w)) or nil
end

function M.capture_pane(pane)
	local b = load().panes[pane]
	if not b then
		return nil
	end
	return rex("capture --trim -s " .. util.shell_quote(b.session.id) .. " -b " .. util.shell_quote(b.id))
end

return M
