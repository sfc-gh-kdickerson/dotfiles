return {
	api_version = 1,
	id = "cursor",
	setup = function(ctx)
		local config = ctx.config
		local git = ctx.git
		local json = ctx.json
		local tmux = ctx.tmux
		local util = ctx.util
		local picker = require("tmux_picker.picker")

		local commands = { agent = true, ["cursor-agent"] = true }
		local status_dir = config.state_home .. "/tmux-picker-agents"
		local chats_dir = config.home .. "/.config/cursor/chats"
		local runtime = config.runtime_dir .. "/tmux-picker.cursor"
		local fire_mode_file = runtime .. ".fire-mode"
		local fire_pane_file = runtime .. ".fire-pane"
		local fire_pid_file = runtime .. ".fire-pid"

		local function pane_number(pane)
			return tostring(pane or ""):gsub("^%%", "")
		end

		local function pane_id(pane)
			pane = pane_number(pane)
			return pane ~= "" and ("%" .. pane) or nil
		end

		local function state_path(pane)
			return status_dir .. "/" .. pane_number(pane) .. ".json"
		end

		local function read_state(pane)
			return json.read(state_path(pane))
		end

		local function read_status(pane)
			local state = read_state(pane)
			if type(state) ~= "table" or state.kind ~= "cursor" or state.pane_id ~= pane then
				return nil
			end
			local pid = tostring(state.pid or "")
			if not pid:match("^%d+$") or tonumber(pid) < 1 or (state.status ~= "ready" and state.status ~= "busy") then
				return nil
			end
			local alive = os.execute("kill -0 " .. util.shell_quote(pid) .. " 2>/dev/null")
			if not (alive == true or alive == 0) or not tmux.pane_owns_pid(pane, pid) then
				return nil
			end
			return state.status, state
		end

		local function text(value)
			return type(value) == "string" and value or ""
		end

		local function chop_title(value)
			value = text(value):gsub("[\r\n]+", "  "):gsub("%s+", " ")
			value = value:gsub("^%s+", ""):gsub("%s+$", "")
			return #value > 80 and value:sub(1, 80) or value
		end

		local function conversation_id(state)
			if type(state.conversation_id) == "string" then
				return state.conversation_id
			elseif type(state.session_id) == "string" then
				return state.session_id
			end
			return nil
		end

		local function title(pane)
			local state = read_state(pane)
			if type(state) ~= "table" then
				return ""
			end
			local id = conversation_id(state)
			local value
			local history
			if id and id:match("^[%w_%-]+$") then
				local handle = io.popen(
					"ls -1 "
						.. util.shell_quote(chats_dir)
						.. "/*/"
						.. util.shell_quote(id)
						.. "/meta.json 2>/dev/null | head -1"
				)
				local metadata = handle and handle:read("*l")
				if handle then
					handle:close()
				end
				if metadata and metadata ~= "" then
					local decoded = json.read(metadata)
					value = type(decoded) == "table" and decoded.title or nil
					history = metadata:gsub("meta%.json$", "prompt_history.json")
				end
			end
			if (not value or value == "") and history then
				local decoded = json.read(history)
				value = type(decoded) == "table" and decoded[1] or nil
			end
			return chop_title(value or state.prompt)
		end

		local function location(session, index, name)
			local value = session .. ":" .. index
			if name and name ~= "" and name ~= "Window" and name ~= index then
				value = value .. "/" .. name
			end
			return value
		end

		local function list_agents(ready_only)
			local rows = {}
			local max_location = 0
			for _, line in
				ipairs(
					tmux.list_panes(
						"#{session_name}\t#{pane_id}\t#{window_index}\t" .. "#{window_name}\t#{pane_current_path}"
					)
				)
			do
				local session, pane, index, window, path = util.split_tab(line, 5)
				local status = pane and read_status(pane)
				if session and status and (not ready_only or status == "ready") then
					local loc = location(session, index, window)
					max_location = math.max(max_location, util.visible_width(loc))
					rows[#rows + 1] = {
						order = status == "ready" and 0 or 1,
						pane = pane,
						location = loc,
						status = status,
						title = title(pane),
						extra = git.decorate(git.ref(path)),
					}
				end
			end
			table.sort(rows, function(left, right)
				if left.order ~= right.order then
					return left.order < right.order
				end
				return left.location < right.location
			end)
			for _, row in ipairs(rows) do
				local color = row.status == "ready" and config.colors.green or config.colors.peach
				local name = util.pad_visible(row.location, max_location)
					.. "  "
					.. color
					.. util.pad_visible(row.status, 5)
					.. config.colors.reset
				if row.title ~= "" then
					name = name .. "  " .. row.title
				end
				ctx.emit({
					kind = "agent",
					target = row.pane,
					name = name,
					extra = row.extra,
				})
			end
		end

		local function fold(text_value, width)
			local output = {}
			for line in text(text_value):gmatch("[^\n]+") do
				local index = 1
				while index <= #line do
					output[#output + 1] = "  " .. line:sub(index, index + width - 1)
					index = index + width
				end
			end
			return output
		end

		local function preview(row)
			local state = read_state(row.target)
			if type(state) ~= "table" then
				return
			end
			local width = math.max(1, math.floor(tonumber(os.getenv("FZF_PREVIEW_COLUMNS")) or 56))
			local status = text(state.status)
			local color = status == "ready" and config.colors.green or config.colors.peach
			local header = color .. (status ~= "" and status or "?") .. config.colors.reset
			local model = text(state.model):gsub("^cursor%-", "")
			if model ~= "" then
				header = header .. "  " .. config.colors.muted .. model .. config.colors.reset
			end
			local tool = text(state.tool)
			if tool ~= "" then
				header = header .. "  " .. config.colors.muted .. tool .. config.colors.reset
			end
			local lines = { header }
			local info = tmux.info(
				row.target,
				"#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t"
					.. "#{pane_current_command}\t#{pane_title}\t"
					.. "#{pane_width}x#{pane_height}\t#{pane_current_path}"
			)
			if info then
				local session, index, window, pane, command, pane_title, size, path = util.split_tab(info, 8)
				lines[#lines + 1] = config.colors.muted
					.. location(session, index, window)
					.. "  "
					.. (pane or row.target)
					.. config.colors.reset
				local pane_meta = command or ""
				if size and size ~= "" then
					pane_meta = pane_meta .. "  " .. size
				end
				if pane_title and pane_title ~= "" and pane_title ~= command then
					pane_meta = pane_meta .. "  " .. pane_title
				end
				lines[#lines + 1] = config.colors.muted .. pane_meta .. config.colors.reset
				if path and path ~= "" then
					lines[#lines + 1] = "path  " .. path .. git.decorate(git.ref(path))
				end
			end
			local pane_title = title(row.target)
			if pane_title ~= "" then
				lines[#lines + 1] = pane_title
			end
			if text(state.prompt) ~= "" then
				lines[#lines + 1] = ""
				lines[#lines + 1] = config.colors.muted .. "you" .. config.colors.reset
				for _, line in ipairs(fold(state.prompt, width)) do
					lines[#lines + 1] = line
				end
			end
			if text(state.response) ~= "" then
				lines[#lines + 1] = ""
				lines[#lines + 1] = config.colors.muted .. "agent" .. config.colors.reset
				for _, line in ipairs(fold(state.response, width)) do
					lines[#lines + 1] = line
				end
			end
			io.write(table.concat(lines, "\n"))
		end

		local function clear_fire()
			os.remove(fire_mode_file)
			os.remove(fire_pane_file)
			os.remove(fire_pid_file)
		end

		local function current_view()
			return (util.read_file(config.view_file) or "agents"):gsub("\n$", "")
		end

		local function fire(pane, message)
			pane = pane_id(pane)
			if not pane or not message or message:match("^%s*$") then
				return false
			end
			local first = true
			for line in (message .. "\n"):gmatch("(.-)\n") do
				if not first and not tmux.send_keys(pane, "C-j") then
					return false
				end
				first = false
				if line ~= "" and not tmux.send_keys(pane, "-l", line) then
					return false
				end
			end
			return tmux.send_keys(pane, "Enter")
		end

		local function restore(notice)
			local prompt = (util.read_file(config.prompt_file) or " "):gsub("\n$", "")
			return {
				raw = "change-prompt(" .. prompt .. ")+clear-query+change-header(" .. picker.legend(
					current_view(),
					notice
				) .. ")",
			}
		end

		local common_keys = {
			{
				key = "ctrl-s",
				chord = "C-s",
				label = "fire",
				action = "cursor.fire",
			},
			{
				key = "ctrl-r",
				chord = "C-r",
				label = "ready",
				action = "cursor.toggle-ready",
			},
		}

		ctx.register_view({
			id = "agents",
			order = 60,
			label = "agents",
			key = "ctrl-e",
			chord = "C-e",
			prompt = "󰚩  ",
			color = config.colors.green,
			keys = common_keys,
			list = function()
				list_agents(false)
			end,
		})
		ctx.register_view({
			id = "agents-ready",
			order = 61,
			label = "ready agents",
			prompt = "󰚩  ",
			color = config.colors.green,
			keys = common_keys,
			list = function()
				list_agents(true)
			end,
		})
		ctx.register_kind("agent", {
			accept = function(row)
				tmux.switch_pane(row.target)
			end,
			preview = preview,
			kill = function(row)
				tmux.kill("pane", row.target)
			end,
		})

		ctx.register_action("cursor.toggle-ready", function(_, view)
			clear_fire()
			local target = view == "agents-ready" and "agents" or "agents-ready"
			return { raw = picker.switch_action(target, os.getenv("TMUX_PICKER_CMD")) }
		end)

		ctx.register_action("cursor.fire", function(row, view)
			if (view ~= "agents" and view ~= "agents-ready") or row.kind ~= "agent" then
				return "ignore"
			end
			local status, state = read_status(row.target)
			if not status or not state then
				return "ignore"
			end
			util.write_file(fire_pane_file, pane_number(row.target) .. "\n")
			util.write_file(fire_pid_file, tostring(state.pid) .. "\n")
			util.write_file(fire_mode_file, "")
			return {
				raw = "change-prompt(fire> )+clear-query"
					.. "+change-header(  type a message   enter send   esc cancel)",
			}
		end)

		ctx.register_hook("enter", function(_, message)
			if not util.file_exists(fire_mode_file) then
				return nil
			end
			os.remove(fire_mode_file)
			local target = util.trim(util.read_file(fire_pane_file) or "")
			local expected_pid = util.trim(util.read_file(fire_pid_file) or "")
			os.remove(fire_pane_file)
			os.remove(fire_pid_file)
			local pane = pane_id(target)
			local _, state = pane and read_status(pane)
			local notice
			if not pane or not state or tostring(state.pid) ~= expected_pid then
				notice = config.colors.peach .. "not sent (no agent)" .. config.colors.reset
			elseif not message or message:match("^%s*$") then
				notice = config.colors.peach .. "not sent (empty)" .. config.colors.reset
			elseif fire(pane, message) then
				notice = config.colors.green .. "sent → " .. target .. config.colors.reset
			else
				notice = config.colors.peach .. "not sent (send-keys)" .. config.colors.reset
			end
			return restore(notice)
		end)

		ctx.register_hook("open", clear_fire)
		ctx.register_hook("view_change", clear_fire)
		ctx.register_hook("escape", function()
			if not util.file_exists(fire_mode_file) then
				return nil
			end
			clear_fire()
			return restore(config.colors.peach .. "not sent" .. config.colors.reset)
		end)

		ctx.register_decorator("command", function(value, data)
			if commands[value] and data.pane_id and read_status(data.pane_id) then
				return config.colors.green .. value .. config.colors.reset
			end
			return value
		end)
	end,
}
