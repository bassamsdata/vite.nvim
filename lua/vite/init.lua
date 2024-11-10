local M

local api = vim.api
local fn = vim.fn

-- Add window tracking
M.current_switcher = {
	buf = nil,
	win = nil,
}
local config = {
	-- project detection configuration
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
		-- Maximum number of project histories to keep
		max_histories = 50,
	},
}

-- Store for buffer access history
local buffer_history = {}
local current_project_root = nil
local history_file_path = ""
local current_buffer = nil
return M
