-- rex-picker entry point: tmux-picker's main with Rex wording, so the same views
-- and plugins in ~/.config/tmux-picker run against the Rex server.
local views = require("tmux_picker.views")
local definition = views.definition
views.definition = function(id)
	local view = definition(id)
	if view and id == "sessions" then
		view.label = "sessions"
	end
	return view
end

dofile(assert(os.getenv("TMUX_PICKER_ROOT"), "TMUX_PICKER_ROOT is not set") .. "/lua/tmux_picker/main.lua")
