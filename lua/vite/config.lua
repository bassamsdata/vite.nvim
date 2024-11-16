local M = {}

-- Default configuration
local defaults = {
	keys = { "a", "s", "d", "f", "g" },
	use_numbers = false,
	show_scores = true,
	score_format = "%.1f",
	select_key = "<CR>",
	modified_icon = "",
	delete_key = "D",
	use_icons = true,
	scoring = {
		frequency_weight = 0.4,
		recency_weight = 0.6,
		recency_decay = 1.0,
	},
	window = {
		width = 60,
		height = 10,
		border = "rounded",
		highlight = "FloatBorder",
		left_padding = "    ",
	},
	split_commands = {
		vertical = "v",
		horizontal = "-",
	},
	project = {
		markers = {
			".git",
			"go.mod",
			"package.json",
			"Cargo.toml",
			"pyproject.toml",
			"pyproject.json",
			"Makefile",
			"README.md",
		},
		max_histories = 50,
	},
	debug = false,
}

-- Validate configuration values
local function validate_config(config)
	-- Ensure weights add up to 1.0
	local total_weight = config.scoring.frequency_weight + config.scoring.recency_weight
	if math.abs(total_weight - 1.0) > 0.001 then
		vim.notify(
			string.format(
				"Vite: frequency_weight and recency_weight should add up to 1.0 (current: %.2f)",
				total_weight
			),
			vim.log.levels.WARN
		)
	end

	-- Ensure window dimensions are reasonable
	if config.window.width < 20 or config.window.width > vim.o.columns then
		config.window.width = math.min(60, vim.o.columns - 4)
	end
	if config.window.height < 3 or config.window.height > vim.o.lines then
		config.window.height = math.min(10, vim.o.lines - 4)
	end

	return config
end

-- Setup configuration
function M.create(opts)
	-- Merge user config with defaults
	local config = vim.tbl_deep_extend("force", defaults, opts or {})

	-- Set debug mode globally
	vim.g.vite_debug = config.debug or false

	-- Validate and return the config
	return validate_config(config)
end

-- Get a specific config value
function M.get(key)
	if not M.config then
		return defaults[key]
	end
	return M.config[key]
end

return M
