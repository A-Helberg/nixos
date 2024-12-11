local wezterm = require("wezterm")

function config()
	local config = wezterm.config_builder()
	config.front_end = "WebGpu"
	config.enable_tab_bar = false

	config.font = wezterm.font("JetBrains Mono")
	config.color_scheme = "Catppuccin Mocha"

	return config
end
