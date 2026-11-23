-- Familiar tmux controls, based on ~/.tmux.conf.
-- Appearance is configured in Rex Settings, separately from this file.
local prefix = "ctrl+space>"
local function bind(key, action, args)
  rex.bind(prefix .. key, action, args)
end

bind("ctrl+space", "pane.send_key", { key = "ctrl+space" })

-- Rex has no last-session action. Track visits through our session shortcuts.
-- History belongs to each app client and starts fresh after config reloads.
local session_history = {}
local function remember_session(ctx, session_id)
  local client = ctx.client_id or "local"
  local history = session_history[client] or {}
  session_history[client] = history
  session_id = session_id or ctx.session_id
  if not session_id then return history end
  for index = #history, 1, -1 do
    if history[index] == session_id then table.remove(history, index) end
  end
  table.insert(history, 1, session_id)
  return history
end

local function available_sessions(ctx)
  local sessions, seen = {}, {}
  local function include(result)
    for _, session in ipairs(result and result.sessions or {}) do
      if not seen[session.session_id] then
        table.insert(sessions, session)
        seen[session.session_id] = #sessions
      end
    end
  end

  local current = rex.call("session.list", {})
  if ctx.server then
    -- Rex routes rex.call to the active remote host. Use the local socket
    -- explicitly to include this Mac, which rex.servers() does not list.
    local home = assert(os.getenv("HOME"))
    local cli = home .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
    local result = rex.exec({ cli, "--autostart=false", "--server",
      home .. "/Library/Application Support/rex/server.sock", "ls", "--json" },
      { timeout = 2 })
    if result and result.ok then include(rex.json.decode(result.stdout)) end
  else
    include(current)
  end
  for _, server in ipairs(rex.servers()) do
    if server == ctx.server then
      include(current)
    else
      include(rex.server(server).call("session.list", {}))
    end
  end
  return sessions, seen
end

rex.action{
  name = "change_session",
  title = "Change Session (Remember Previous)",
  run = function(ctx)
    remember_session(ctx)
    rex.client.queue("session.switch")
  end,
}
rex.action{
  name = "cycle_session",
  title = "Cycle Session (Remember Previous)",
  args = { direction = "string" },
  run = function(ctx, args)
    remember_session(ctx)
    rex.client.queue("session." .. args.direction)
  end,
}
rex.action{
  name = "last_session",
  title = "Last Session",
  run = function(ctx)
    local history = remember_session(ctx)
    local sessions, available = available_sessions(ctx)
    local target
    for index = 2, #history do
      if available[history[index]] then target = history[index]; break end
    end
    -- With two sessions across all hosts, the other is the only destination.
    if not target and #sessions == 2 then
      for _, session in ipairs(sessions) do
        if session.session_id ~= ctx.session_id then target = session.session_id end
      end
    end
    if target then
      -- session.select is restricted to the current host in this Rex build.
      -- Native cycling follows the app's host/session order across machines.
      local from, to = available[ctx.session_id], available[target]
      if not from then return end
      local steps = (to - from) % #sessions
      local direction = "next"
      if steps > #sessions / 2 then
        direction, steps = "previous", #sessions - steps
      end
      for _ = 1, steps do rex.client.queue("session." .. direction) end
    end
  end,
}

-- Windows in tmux are tabs in Rex; both count from 1 here.
bind("c", "client.tab.new")
bind("n", "client.tab.next")
bind("ctrl+n", "client.tab.next")
bind("ctrl+p", "client.tab.previous")
for index = 1, 9 do
  bind(tostring(index), "client.tab.goto", { index = index })
end
bind(",", "client.tab.rename")
bind("shift+4", "session.rename") -- $
bind("o", "change_session")
rex.bind("cmd+k", "change_session")
bind("l", "last_session")
bind("shift+9", "cycle_session", { direction = "previous" }) -- (
bind("shift+0", "cycle_session", { direction = "next" })     -- )
bind("d", "client.window.close") -- Server keeps the session running.

-- Rex's native splits inherit the source terminal's working directory.
bind("shift+5", "pane.split", { direction = "right" }) -- %
bind("shift+'", "pane.split", { direction = "down" })  -- "
bind("z", "pane.zoom")
bind("x", "client.close") -- Also closes a tab when it has only one pane.
bind("shift+x", "client.tab.close")

bind("h", "pane.focus", { direction = "left" })
bind("j", "pane.focus", { direction = "down" })
bind("k", "pane.focus", { direction = "up" })

-- Direct navigation, like vim-tmux-navigator's root-table bindings.
-- Let editors, fzf, and nested tmux keep their own navigation keys.
rex.action{
  name = "navigate_pane",
  title = "Navigate Pane (Editor Aware)",
  args = { key = "string", direction = "string" },
  run = function(ctx, args)
    local process = rex.block.call("com.superlogical.terminal", "process", {})
    local foreground = process and process.foreground
    local name = foreground and foreground.name or ""
    name = name:lower():match("([^/]+)$") or ""
    local is_editor = name == "nvim" or name == "vim" or name == "view"
      or name == "vi" or name == "gvim" or name == "vimdiff"
      or name == "nvimdiff" or name == "fzf"
    local is_multiplexer = name == "tmux" or name == "tmate" or name:match("^tmux:")
    if not foreground or is_editor or is_multiplexer then
      rex.client.queue("pane.send_key", { key = args.key })
    else
      rex.client.queue("pane.focus", { direction = args.direction })
    end
  end,
}
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, "navigate_pane", {
    key = "ctrl+" .. key,
    direction = direction,
  })
end

for _, direction in ipairs({ "left", "down", "up", "right" }) do
  bind(direction, "pane.focus", { direction = direction })
  -- Rex uses percent of the split, rather than tmux's number of cells.
  -- Each resize requires the prefix; Rex has no tmux repeat-time timer.
  bind("ctrl+" .. direction, "pane.resize", {
    direction = direction,
    amount = 5,
  })
end
bind("ctrl+l", "pane.send_key", { key = "ctrl+l" })
bind("shift+r", "client.config.reload") -- R, as in your running tmux.
bind("shift+;", "client.palette.toggle") -- : opens the command palette.
bind("shift+/", "client.palette.toggle") -- ? shows available Rex commands.

-- Ghostty input customizations: delete a word, and send a literal newline.
rex.bind("alt+backspace", "com.superlogical.terminal.write", { data = "\27\127" })
rex.bind("shift+enter", "com.superlogical.terminal.write", { data = "\n" })

-- A persistent scratch shell per window, shown as a centered floating pane.
local popup_bounds = { 0.15, 0.15, 0.70, 0.70 } -- x, y, width, height
local popup_return = {}
local popup_zoom = {}
rex.action{
  name = "toggle_popup",
  title = "Toggle Scratch Popup",
  run = function(ctx)
    local view = assert(rex.session.view{})
    local window_id = view.active_window_id
    local popup_label = "rex-scratch-popup:" .. window_id
    local blocks = assert(rex.session.list_blocks{}).blocks or {}
    local popup
    for _, block in ipairs(blocks) do
      -- Ctrl+P is the picker's own projects view.
      if block.block_id == ctx.block_id and block.label == "rex-picker-popup" then
        assert(rex.call("com.superlogical.terminal.write", {
          session_id = ctx.session_id, block_id = block.block_id, args = { data = "\16" },
        }))
        return
      end
      if block.label == popup_label then popup = block end
    end
    -- Keep the old shared shell in its current window when upgrading the config.
    if not popup then
      for _, block in ipairs(blocks) do
        if block.label == "rex-scratch-popup"
          and (block.window_id == window_id or block.placement ~= "placed") then
          assert(rex.session.set_block_label{ block_id = block.block_id, label = popup_label })
          popup = block
          break
        end
      end
    end

    if popup and ctx.block_id == popup.block_id then
      assert(rex.session.detach_block{ block_id = popup.block_id })
      -- Detaching hides the shell without stopping it. Restore the source pane
      -- when it still exists; the server otherwise picks another pane itself.
      if popup_return[window_id] then
        rex.session.focus_block{ block_id = popup_return[window_id] }
      end
      if popup_zoom[window_id] then
        rex.session.zoom_block{ block_id = popup_zoom[window_id], zoom = true }
      end
      return
    end

    local window
    for _, candidate in ipairs(view.windows) do
      if candidate.window_id == window_id then window = candidate end
    end
    popup_return[window_id] = ctx.block_id
    popup_zoom[window_id] = window and window.zoomed_block_id
    if popup_zoom[window_id] then
      assert(rex.session.zoom_block{ block_id = popup_zoom[window_id], zoom = false })
    end
    if popup then
      if popup.placement ~= "placed" or popup.window_id ~= window_id then
        -- Rex reattaches an existing block via a split before it can float it.
        assert(rex.session.move_block{
          block_id = popup.block_id,
          anchor_block_id = ctx.block_id,
        })
        assert(rex.session.float_block{ block_id = popup.block_id, bounds = popup_bounds })
      end
      assert(rex.session.focus_block{ block_id = popup.block_id })
    else
      local process = rex.block.call("com.superlogical.terminal", "process", {})
      local source = process and (process.foreground or process.child)
      local options = {}
      if source and source.cwd then options.cwd = source.cwd end
      assert(rex.session.new_layer{
        window_id = window_id,
        bounds = popup_bounds,
        focus = true,
        layout = { block = {
          flavor = "com.superlogical.terminal.shell",
          label = popup_label,
          options = options,
        } },
      })
    end
  end,
}
rex.bind("ctrl+p", "toggle_popup")

rex.action{
  name = "lazygit_popup",
  title = "Open Lazygit Popup",
  run = function(ctx)
    local view = assert(rex.session.view{})
    for _, window in ipairs(view.windows) do
      if window.window_id == view.active_window_id then
        for _, layer in ipairs(window.layers) do
          for _, block in ipairs(layer.blocks or {}) do
            if block.label == "rex-lazygit-popup" then
              assert(rex.session.focus_block{ block_id = block.block_id })
              return
            end
          end
        end
        if window.zoomed_block_id then
          assert(rex.session.zoom_block{ block_id = window.zoomed_block_id, zoom = false })
        end
      end
    end
    local process = rex.block.call("com.superlogical.terminal", "process", {})
    local source = process and (process.foreground or process.child)
    local options = {
      command = { os.getenv("HOME") .. "/.nix-profile/bin/lazygit" },
      shell = "none",
      exit = { on_completion = true },
    }
    if source and source.cwd then options.cwd = source.cwd end
    assert(rex.session.new_layer{
      bounds = popup_bounds,
      focus = true,
      layout = { block = {
        flavor = "com.superlogical.terminal.shell",
        label = "rex-lazygit-popup",
        options = options,
      } },
    })
  end,
}
bind("g", "lazygit_popup")

-- tmux-picker's views (snowbox projects, Cursor agents, sessions) through
-- ~/scripts/rex-picker, run on the host of the focused session. The picker stays
-- resident, one per session: after a pick or Esc it minimizes its layer and
-- starts a fresh fzf, so the next press restores an already drawn picker at its
-- size. Each call here is a round trip to the session's host, so keep them few.
local picker_bounds = { 0.15, 0.10, 0.70, 0.80 }
local picker_label = "rex-picker-popup"
-- The control bytes fzf binds to each view's switch key (C-p, C-e, C-t, C-x).
local picker_view_keys = { projects = "\16", agents = "\5", sessions = "\20", zoxide = "\24" }
rex.action{
  name = "picker_popup",
  title = "Open Picker Popup",
  args = { view = "string" },
  run = function(ctx, args)
    local view = assert(rex.session.view{})
    local layer_id, picker_id, here
    for _, window in ipairs(view.windows) do
      local active = window.window_id == view.active_window_id
      if active and window.zoomed_block_id then
        assert(rex.session.zoom_block{ block_id = window.zoomed_block_id, zoom = false })
      end
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.kind == "floating" and layer.blocks or {}) do
          if block.label == picker_label and (active or not picker_id) then
            layer_id, picker_id, here = layer.layer_id, block.block_id, active
          end
        end
      end
    end
    if picker_id then
      -- Switch the view while hidden so the stale list never shows.
      assert(rex.call("com.superlogical.terminal.write", {
        session_id = ctx.session_id,
        block_id = picker_id,
        args = { data = picker_view_keys[args.view] or picker_view_keys.projects },
      }))
      if here then
        assert(rex.session.set_layer_state{ layer_id = layer_id, state = "normal", focus = true })
        return
      end
      -- Layers can't change windows, but blocks can. Moving the picker beside a
      -- placeholder in a new floating layer, rather than beside a tiled pane,
      -- leaves this window's layout alone; closing the placeholder lets the
      -- picker fill the layer.
      local placeholder = assert(rex.session.new_layer{
        bounds = picker_bounds,
        layout = { block = {
          flavor = "com.superlogical.terminal.shell",
          label = "rex-picker-placeholder",
          options = { command = { "sleep", "60" }, shell = "none", exit = { on_completion = true } },
        } },
      }).block_ids[1]
      assert(rex.session.move_block{ block_id = picker_id, anchor_block_id = placeholder, ratio = 0.02 })
      assert(rex.call("block.close", { session_id = ctx.session_id, block_id = placeholder }))
      assert(rex.session.focus_block{ block_id = picker_id })
      return
    end
    local launch = [[
picker="$HOME/scripts/rex-picker"
if [ -x "$picker" ]; then exec "$picker" --resident "$1"; fi
echo "rex-picker is not installed on this host"; sleep 2
]]
    assert(rex.session.new_layer{
      bounds = picker_bounds,
      focus = true,
      layout = { block = {
        flavor = "com.superlogical.terminal.shell",
        label = picker_label,
        options = {
          command = { "/bin/sh", "-c", launch, "rex-picker", args.view },
          shell = "none",
          exit = { on_completion = true },
        },
      } },
    })
  end,
}
bind("p", "picker_popup", { view = "projects" })
bind("e", "picker_popup", { view = "agents" })

bind("[", "pane.copy_mode.enter")

-- Remaining gaps: status-line formats, lock-client, and the worktree plugin binding.
