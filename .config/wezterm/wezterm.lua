local wezterm = require 'wezterm'
-- This will hold the configuration.
local config = wezterm.config_builder()
-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.font = wezterm.font 'JetBrains Mono'
config.font_size = 15.0
config.line_height = 0.94
config.harfbuzz_features = { 'calt=0' }

config.color_scheme = 'Catppuccin Mocha'
config.colors = { background = "#000000" }
config.window_background_opacity = 0.8 -- Adjust value between 0.0 (fully transparent) and 1.0 (opaque)
-- config.macos_window_background_blur = 8
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

wezterm.on('toggle-opacity', function(window, pane)
  local overrides = window:get_config_overrides() or {}
  if overrides.window_background_opacity == nil or overrides.window_background_opacity == 1.0 then
    -- Set to desired transparency level
    overrides.window_background_opacity = 0.8
    overrides.colors = { background = "#000000" }
  else
    -- Reset to fully opaque
    overrides.window_background_opacity = 1.0
    overrides.colors = { background = "#1e1e2e" }
  end
  window:set_config_overrides(overrides)
end)

-- Define key binding to toggle opacity
config.keys = {
  {
    key = 'T', -- Choose any key you'd like
    mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent('toggle-opacity'),
  },
}

return config
