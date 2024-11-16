local M = {}

-- Core state that needs to be accessible across modules
M.state = {
	buffer_history = {},
	current_project_root = nil,
	history_file_path = "",
	current_buffer = nil,
	current_switcher = { buf = nil, win = nil },
}

-- Will be populated in setup()
M.config = {}

-- Setup function
function M.setup(opts)
	-- Load config module
	local config = require("vite.config")
	M.config = config.create(opts)

	-- Initialize core functionality
	local history = require("vite.history")
	local scoring = require("vite.scoring")
	-- Initialize modules with config
	history.initialize(M.state, M.config)
	scoring.initialize(M.config)

	-- Set up autocommands
	local function create_autocommands()
		local group = vim.api.nvim_create_augroup("Vite", { clear = true })

		vim.api.nvim_create_autocmd("BufEnter", {
			group = group,
			callback = function()
				local current_buf = vim.api.nvim_get_current_buf()
				if scoring.is_valid_buffer(current_buf) then
					scoring.update_history(current_buf, M.state)
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

	create_autocommands()
end

-- Main function to show buffer switcher
function M.show()
	local ui = require("vite.ui")
	ui.show_switcher(M.state, M.config)
end

return M
