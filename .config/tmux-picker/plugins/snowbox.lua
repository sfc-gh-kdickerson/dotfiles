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
		local show_archived_file = config.runtime_dir .. "/tmux-picker.snowbox-archived"

		local function badge()
			return project_color .. project_icon .. "\27[39m"
		end

		local function archived_badge()
			return config.colors.muted .. project_icon .. "\27[39m"
		end

		local function session_badge()
			return config.colors.blue .. config.icons.session .. "\27[39m"
		end

		local function project_path(slug)
			return projects_dir .. "/" .. slug
		end

		local function archive_path(slug)
			return projects_dir .. "/archive/" .. slug
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

		local function showing_archived()
			return util.file_exists(show_archived_file)
		end

		local function set_showing_archived(on)
			if on then
				util.write_file(show_archived_file, "1\n")
			else
				os.remove(show_archived_file)
			end
		end

		local projects_cache
		local archived_cache

		local function read_project_dir(dir, name)
			local path = dir .. "/" .. name
			local data = json.read(path .. "/project.json")
			if type(data) ~= "table" or data[1] ~= nil then
				return nil
			end
			data.slug = data.slug or name
			data.title = data.title or name
			data.path = path
			data.stacks = data.stacks or {}
			return data
		end

		local function load_projects()
			if projects_cache then
				return projects_cache
			end
			local output = {}
			for _, name in ipairs(util.lines("ls -1 " .. util.shell_quote(projects_dir) .. " 2>/dev/null")) do
				if name ~= "" and name ~= "archive" then
					local data = read_project_dir(projects_dir, name)
					if data and (data.status or "active") == "active" then
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

		local function load_archived_projects()
			if archived_cache then
				return archived_cache
			end
			local output = {}
			local archive_dir = projects_dir .. "/archive"
			for _, name in ipairs(util.lines("ls -1 " .. util.shell_quote(archive_dir) .. " 2>/dev/null")) do
				if name ~= "" then
					local data = read_project_dir(archive_dir, name)
					if data then
						output[#output + 1] = data
					end
				end
			end
			table.sort(output, function(left, right)
				return (left.slug or "") < (right.slug or "")
			end)
			archived_cache = output
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

		local function emit_archived()
			for _, project in ipairs(load_archived_projects()) do
				local slug = project.slug
				if slug and project.path then
					local extra = stack_labels(project)
					if project.title and project.title ~= "" and project.title:lower() ~= slug:lower() then
						extra = " " .. config.colors.muted .. project.title .. config.colors.reset .. extra
					end
					ctx.emit({
						kind = "archived-project",
						target = project.path,
						name = archived_badge() .. " " .. slug,
						source = "archived",
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

		local function unarchive_project(slug)
			local ok, err = run_project("unarchive", slug)
			if not ok then
				return false, err
			end
			projects_cache = nil
			archived_cache = nil
			return true
		end

		local function unarchive_and_connect(slug)
			local ok, err = unarchive_project(slug)
			if not ok then
				error(err)
			end
			local data = json.read(project_path(slug) .. "/project.json")
			local stacks = type(data) == "table" and data.stacks or {}
			if type(stacks) == "table" and #stacks > 0 then
				ctx.notify("unarchived " .. slug .. " — project relink " .. slug .. " to restore stacks")
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
			elseif util.file_exists(archive_path(slug) .. "/project.json") then
				unarchive_and_connect(slug)
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
				key = "ctrl-n",
				chord = "C-n",
				label = "create",
				action = "snowbox.create",
			},
			{
				key = "ctrl-a",
				chord = "C-a",
				label = "archive",
				action = "snowbox.archive",
			},
			{
				key = "ctrl-u",
				chord = "C-u",
				label = "archived",
				action = "snowbox.toggle-archived",
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
				if showing_archived() then
					emit_archived()
				end
			end,
			query = query,
		})

		ctx.register_kind("project", {
			accept = function(row)
				connect_path(row.target)
			end,
			preview = preview,
		})

		ctx.register_kind("archived-project", {
			accept = function(row)
				local slug = project_slug(row.target)
				if not slug then
					return
				end
				unarchive_and_connect(slug)
			end,
			preview = preview,
		})

		local function typed_slug(row)
			return util.trim(row.query or ""):lower()
		end

		ctx.register_action("snowbox.create", {
			pending = function(row, view)
				if view ~= "projects" then
					return
				end
				local slug = typed_slug(row)
				if not is_slug(slug) then
					return
				end
				if util.file_exists(project_path(slug) .. "/project.json") then
					return
				end
				if util.file_exists(archive_path(slug) .. "/project.json") then
					return
				end
				return config.colors.muted .. "creating " .. slug .. "…" .. config.colors.reset
			end,
			run = function(row, view)
				if view ~= "projects" then
					return "ignore"
				end
				local slug = typed_slug(row)
				if slug == "" then
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. "type a slug" .. config.colors.reset,
					}
				end
				if not is_slug(slug) then
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. "invalid slug" .. config.colors.reset,
					}
				end
				if util.file_exists(project_path(slug) .. "/project.json") then
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. slug .. " exists" .. config.colors.reset,
					}
				end
				if util.file_exists(archive_path(slug) .. "/project.json") then
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. slug .. " is archived" .. config.colors.reset,
					}
				end
				local ok, err = run_project("new", slug)
				if not ok then
					ctx.notify(err)
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. "create failed" .. config.colors.reset,
					}
				end
				projects_cache = nil
				return {
					reload = true,
					view = "projects",
					notice = config.colors.green .. "created " .. slug .. config.colors.reset,
				}
			end,
		})

		ctx.register_action("snowbox.toggle-archived", function(_, view)
			if view ~= "projects" then
				return "ignore"
			end
			set_showing_archived(not showing_archived())
			return {
				reload = true,
				view = "projects",
			}
		end)

		ctx.register_action("snowbox.archive", {
			pending = function(row, view)
				if view ~= "projects" then
					return
				end
				local slug = project_slug(row.target)
				if not slug then
					return
				end
				if row.kind == "archived-project" then
					return config.colors.muted .. "unarchiving " .. slug .. "…" .. config.colors.reset
				end
				if row.kind == "project" then
					return config.colors.muted .. "archiving " .. slug .. "…" .. config.colors.reset
				end
			end,
			run = function(row, view)
				if view ~= "projects" then
					return "ignore"
				end
				local slug = project_slug(row.target)
				if row.kind == "archived-project" then
					if not slug or row.target ~= archive_path(slug) or not util.file_exists(row.target .. "/project.json") then
						return {
							reload = true,
							view = "projects",
							notice = config.colors.peach .. "unarchive failed" .. config.colors.reset,
						}
					end
					local ok, err = unarchive_project(slug)
					if not ok then
						ctx.notify(err)
						return {
							reload = true,
							view = "projects",
							notice = config.colors.peach .. "unarchive failed" .. config.colors.reset,
						}
					end
					tmux.ensure_session(slug, project_path(slug))
					return {
						reload = true,
						view = "projects",
						notice = config.colors.green .. "unarchived " .. slug .. config.colors.reset,
					}
				end
				if row.kind ~= "project" then
					return "ignore"
				end
				if not slug or row.target ~= project_path(slug) or not util.file_exists(row.target .. "/project.json") then
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. "archive failed" .. config.colors.reset,
					}
				end
				local ok, err = run_project("archive", slug)
				if not ok then
					ctx.notify(err)
					return {
						reload = true,
						view = "projects",
						notice = config.colors.peach .. "archive failed" .. config.colors.reset,
					}
				end
				projects_cache = nil
				archived_cache = nil
				if tmux.has_session(slug) then
					tmux.kill("session", slug)
				end
				return {
					reload = true,
					view = "projects",
					notice = config.colors.green .. "archived " .. slug .. config.colors.reset,
				}
			end,
		})

		ctx.register_hook("open", function()
			os.remove(show_archived_file)
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
