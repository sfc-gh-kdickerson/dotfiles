-- Run with `rex do`: one snapshot of every session, window, and terminal block on
-- this server, plus which sessions each Rex app is showing. rex-picker reads it
-- in place of tmux's list-sessions, list-windows, and list-panes.
local out = { sessions = {}, clients = {} }

local all = assert(rex.call("session.attach_all", { event_scope = "session" }))
for _, s in ipairs(all.sessions or {}) do
  local session = { id = s.session_id, label = s.label, windows = {} }
  local view = rex.call("session.view", { session_id = s.session_id })
  if view then
    session.active_window_id = view.active_window_id
    for index, w in ipairs(view.windows or {}) do
      local window = {
        id = w.window_id,
        label = w.label,
        index = index,
        focused = w.focused_block_id,
        zoomed = w.zoomed_block_id,
        blocks = {},
      }
      for _, layer in ipairs(w.layers or {}) do
        for _, b in ipairs(layer.blocks or {}) do
          local block = { id = b.block_id, label = b.label, floating = layer.kind ~= "tiled" }
          if b.creator_name == "com.superlogical.terminal" then
            local p = rex.call("com.superlogical.terminal.process", {
              session_id = s.session_id,
              block_id = b.block_id,
            })
            if p then
              local foreground, child = p.foreground or {}, p.child or {}
              block.cwd = foreground.cwd or child.cwd
              -- argv0 names what was run; the process name can be a thread
              -- name (the agent CLI reports "MainThread").
              local argv0 = ((foreground.argv0 or ""):match("([^/]+)$") or ""):gsub("^%-", "")
              block.command = argv0 ~= "" and argv0 or foreground.name or child.name
              block.pid = child.pid
            end
          end
          table.insert(window.blocks, block)
        end
      end
      table.insert(session.windows, window)
    end
  end
  table.insert(out.sessions, session)
end

local clients = rex.call("client.list", {})
for _, c in ipairs(clients and clients.clients or {}) do
  if c.info and c.info.kind == "app" then
    table.insert(out.clients, { id = c.client_id, sessions = c.session_ids or {} })
  end
end

return out
