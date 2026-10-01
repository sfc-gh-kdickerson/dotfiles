-- Local plugins in plugins/ (cursor, snowbox) own work-specific views.
-- tmux-picker itself is the TPM plugin; disable its bundled Agents view so
-- it does not collide with the Cursor plugin's `agents` view.
return {
	bundled_plugins = {
		zoxide = true,
		agents = false,
	},
}
