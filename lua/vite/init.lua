local M = {}

-- M.config = {}
-- Core state that needs to be accessible across modules
M.state = {
	buffer_history = {},
	current_project_root = nil,
	history_file_path = "",
	current_buffer = nil,
	current_switcher = { buf = nil, win = nil },
}

local function measure(name, fn)
	local start = vim.uv.hrtime()
	local result = { fn() } -- Capture all return values in a table
	local duration = (vim.uv.hrtime() - start) / 1000000
	vim.notify(string.format("History: %s took %.2fms", name, duration))
	---@diagnostic disable-next-line: deprecated
	return unpack(result) -- Return all values
end

-- Track initialization state
local config = require("vite.config")
local scoring = require("vite.scoring")
local history = require("vite.history")

-- Setup function
function M.setup(opts)
	M.config = config.create(opts or {})
	measure("history", function()
		history.initialize(M.state, M.config)
	end)
	measure("scoring", function()
		scoring.initialize(M.config)
	end)

	-- Measure autocommand setup
	local group = vim.api.nvim_create_augroup("Vite", { clear = true })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			if scoring.is_valid_buffer(args.buf) then
				scoring.update_history(args.buf, M.state)
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "FocusLost", "VimLeavePre" }, {
		group = group,
		callback = function()
			history.save_to_file(M.state)
			history.cleanup_old_histories(M.config)
		end,
	})

	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			history.save_to_file(M.state)
			history.initialize(M.state, M.config)
		end,
	})
end

-- Main function to show buffer switcher
function M.show()
	local ui = require("vite.ui")
	ui.show_switcher(M.state, M.config)
end

return M
