return {
	api_version = 1,
	id = "snowbox",
	setup = function(ctx)
		local config = ctx.config
		local git = ctx.git
		local json = ctx.json
		local tmux = ctx.tmux
		local util = ctx.util

		local snowbox = os.getenv("SNOWBOX") or "/home/repo/snowbox-kdickerson"
		local projects_dir = os.getenv("PROJECTS") or (snowbox .. "/projects")
		local project_command = os.getenv("PROJECT_COMMAND") or (config.home .. "/scripts/project")
		local project_icon = ""
		local project_color = config.colors.mauve

		local function badge()
			return project_color .. project_icon .. "\27[39m"
		end

		local function session_badge()
			return config.colors.blue .. config.icons.session .. "\27[39m"
		end

		local function project_path(slug)
			return projects_dir .. "/" .. slug
		end

		local function project_slug(path)
			local slug = util.basename(path)
			return slug and slug:lower() or nil
		end

		local function is_slug(value)
			return value ~= ""
				and not value:find("[^a-z0-9%-]")
				and value:sub(1, 1) ~= "-"
				and value:sub(-1) ~= "-"
				and not value:find("%-%-")
		end

		local projects_cache

		local function load_projects()
			if projects_cache then
				return projects_cache
			end
			local output = {}
			for _, name in ipairs(util.lines("ls -1 " .. util.shell_quote(projects_dir) .. " 2>/dev/null")) do
				if name ~= "" and name ~= "archive" then
					local path = project_path(name)
					local data = json.read(path .. "/project.json")
					if type(data) == "table" and data[1] == nil and (data.status or "active") == "active" then
						data.slug = data.slug or name
						data.title = data.title or name
						data.path = path
						data.stacks = data.stacks or {}
						output[#output + 1] = data
					end
				end
			end
			table.sort(output, function(left, right)
				return (left.slug or "") < (right.slug or "")
			end)
			projects_cache = output
			return output
		end

		local function slug_set(projects)
			local output = {}
			for _, project in ipairs(projects or load_projects()) do
				if project.slug then
					output[project.slug:lower()] = true
				end
			end
			return output
		end

		local function live_sessions()
			local output = {}
			for _, line in ipairs(tmux.list_session_paths()) do
				local name = util.split_tab(line, 4)
				if name and name ~= "" then
					output[name:lower()] = true
				end
			end
			return output
		end

		local function stack_labels(project)
			local seen = {}
			local labels = {}
			for _, stack in ipairs(project.stacks or {}) do
				local label = (stack.graphite and stack.graphite.stack) or stack.branch
				if label and label ~= "" and not seen[label] then
					seen[label] = true
					labels[#labels + 1] = label
				end
			end
			return #labels > 0 and git.decorate(table.concat(labels, "  ")) or ""
		end

		local function emit_projects(options)
			options = options or {}
			local live = options.live or live_sessions()
			for _, project in ipairs(options.projects or load_projects()) do
				local slug = project.slug
				if slug and project.path and (options.all or not live[slug:lower()]) then
					local name = badge() .. " " .. slug
					if live[slug:lower()] then
						name = badge() .. " " .. session_badge() .. " " .. slug
					end
					local extra = stack_labels(project)
					if project.title and project.title ~= "" and project.title:lower() ~= slug:lower() then
						extra = " " .. config.colors.muted .. project.title .. config.colors.reset .. extra
					end
					ctx.emit({
						kind = "project",
						target = project.path,
						name = name,
						source = "project",
						extra = extra,
					})
				end
			end
		end

		local function connect_path(path)
			local slug = project_slug(path)
			if not slug then
				return
			end
			tmux.ensure_session(slug, path)
			tmux.switch_session(slug)
		end

		local function run_project(verb, slug)
			local command = "PATH="
				.. util.shell_quote(config.path_prefix)
				.. " "
				.. util.shell_quote(project_command)
				.. " "
				.. util.shell_quote(verb)
				.. " "
				.. util.shell_quote(slug)
			local handle = io.popen(command .. " 2>&1")
			local output = handle and handle:read("*a") or ""
			local ok = handle and handle:close()
			if ok then
				return true
			end
			local message = util.trim(output):match("^[^\n]+")
			return false, message or ("project " .. verb .. " " .. slug .. " failed")
		end

		local function create(slug)
			ctx.notify("creating project " .. slug)
			local ok, err = run_project("new", slug)
			if not ok then
				error(err)
			end
			connect_path(project_path(slug))
		end

		local function query(value)
			value = util.trim(value)
			if value == "" then
				return
			end
			local slug = value:lower()
			if tmux.has_session(slug) then
				tmux.switch_session(slug)
			elseif util.file_exists(project_path(slug) .. "/project.json") then
				connect_path(project_path(slug))
			elseif is_slug(slug) then
				create(slug)
			else
				tmux.ensure_session(value)
				tmux.switch_session(value)
			end
		end

		local function preview(row)
			local project = json.read(row.target .. "/project.json")
			if type(project) ~= "table" then
				io.write(config.colors.peach, "no project.json", config.colors.reset, "\n")
				return
			end
			io.write(config.colors.green, project.slug or row.target, config.colors.reset, "\n")
			if project.title and project.title ~= "" and project.title:lower() ~= (project.slug or ""):lower() then
				io.write(config.colors.muted, project.title, config.colors.reset, "\n")
			end
			io.write(config.colors.muted, row.target, config.colors.reset, "\n")
			for _, stack in ipairs(project.stacks or {}) do
				local label = (stack.graphite and stack.graphite.stack) or stack.branch or ""
				io.write("\n", stack.link or "", "  ", stack.repo or "")
				if label ~= "" then
					io.write("  ", config.colors.muted, label, config.colors.reset)
				end
				io.write("\n")
			end
		end

		local function with_project_badge(value)
			local icon, rest = value:match("^(.-) (.+)$")
			if not icon then
				return badge() .. " " .. value
			end
			return icon .. " " .. badge() .. " " .. rest
		end

		local project_keys = {
			{
				key = "ctrl-a",
				chord = "C-a",
				label = "archive",
				action = "snowbox.archive",
			},
		}

		ctx.register_view({
			id = "projects",
			order = 20,
			label = "projects",
			key = "ctrl-p",
			chord = "C-p",
			prompt = project_icon .. "  ",
			color = project_color,
			keys = project_keys,
			list = function()
				emit_projects({ all = true })
			end,
			query = query,
		})

		ctx.register_kind("project", {
			accept = function(row)
				connect_path(row.target)
			end,
			preview = preview,
		})

		ctx.register_action("snowbox.archive", function(row, view)
			if view ~= "projects" or row.kind ~= "project" then
				return "ignore"
			end
			local slug = project_slug(row.target)
			if not slug or row.target ~= project_path(slug) or not util.file_exists(row.target .. "/project.json") then
				return {
					reload = true,
					view = "projects",
					notice = config.colors.peach .. "archive failed" .. config.colors.reset,
				}
			end
			ctx.notify("archiving " .. slug)
			local ok, err = run_project("archive", slug)
			if not ok then
				ctx.notify(err)
				return {
					reload = true,
					view = "projects",
					notice = config.colors.peach .. "archive failed" .. config.colors.reset,
				}
			end
			if tmux.has_session(slug) then
				tmux.kill("session", slug)
			end
			return {
				reload = true,
				view = "projects",
				notice = config.colors.green .. "archived " .. slug .. config.colors.reset,
			}
		end)

		ctx.register_supplement("sessions", function()
			emit_projects({ all = false })
		end)

		ctx.register_decorator("session", function(value, data)
			return data.name and slug_set()[data.name:lower()] and with_project_badge(value) or value
		end)
		ctx.register_decorator("window", function(value, data)
			return data.session and slug_set()[data.session:lower()] and with_project_badge(value) or value
		end)
		ctx.register_decorator("pane", function(value, data)
			return data.session and slug_set()[data.session:lower()] and with_project_badge(value) or value
		end)
	end,
}
