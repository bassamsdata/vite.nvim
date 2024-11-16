local M = {}
local api = vim.api

-- Add performance monitoring
local function measure_time(fn, name)
	local start = vim.uv.hrtime()
	local result = fn()
	local end_time = vim.uv.hrtime()
	M.debug_log(string.format("%s took %0.3fms", name, (end_time - start) / 1e6))
	return result
end

-- Improve debug logging
local log_levels = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

function M.log(message, level, data)
	level = level or log_levels.INFO
	if level >= (vim.g.vite_log_level or log_levels.WARN) then
		local msg = type(message) == "string" and message or vim.inspect(message)
		if data then
			msg = msg .. ": " .. vim.inspect(data)
		end
		vim.notify(msg, level)
	end
end

-- Check if switcher window is currently open
function M.is_switcher_open(state)
	return state.current_switcher
		and state.current_switcher.win ~= nil
		and state.current_switcher.buf ~= nil
		and api.nvim_win_is_valid(state.current_switcher.win)
		and api.nvim_buf_is_valid(state.current_switcher.buf)
end

-- Delete buffer safely
function M.delete_buffer(buf_id)
	-- Try to delete the buffer
	local success = pcall(api.nvim_buf_delete, buf_id, { force = false })
	if not success then
		vim.notify("Cannot delete buffer: Buffer is modified", vim.log.levels.WARN)
		return false
	end
	return true
end

-- Refresh the switcher display
function M.refresh_switcher(state, config)
	if not M.is_switcher_open(state) then
		return
	end
	local scoring = require("vite.scoring")
	local ui = require("vite.ui")
	-- Get fresh list of buffers
	local buffers = scoring.get_sorted_buffers(state)
	local current_buffer = api.nvim_get_current_buf()
	-- Store current cursor position
	local cursor = api.nvim_win_get_cursor(state.current_switcher.win)
	-- Redisplay buffers
	local key_map, _, current_line = ui.display_buffers(state.current_switcher.buf, buffers, current_buffer, config)
	-- Update the stored key_map in state if needed
	state.current_switcher.key_map = key_map
	-- Adjust cursor position
	if cursor[1] > #buffers then
		-- If we were at the end, stay at the end
		api.nvim_win_set_cursor(state.current_switcher.win, { #buffers, cursor[2] })
	elseif current_line then
		-- If current buffer is visible, move to it
		local fixed_col = #config.window.left_padding + 7
		api.nvim_win_set_cursor(state.current_switcher.win, { current_line, fixed_col })
	else
		-- Stay at the same line if possible
		local line = math.min(cursor[1], #buffers)
		api.nvim_win_set_cursor(state.current_switcher.win, { line, cursor[2] })
	end
end

-- Set fixed cursor column position
function M.set_fixed_cursor_column(win, line, left_padding)
	local fixed_col = #left_padding + 7 -- Position after key and icon
	api.nvim_win_set_cursor(win, { line, fixed_col })
end

-- Debug logging helper
function M.debug_log(message, data)
	if vim.g.vite_debug then
		local msg = type(message) == "string" and message or vim.inspect(message)
		if data then
			msg = msg .. ": " .. vim.inspect(data)
		end
		vim.notify(msg, vim.log.levels.DEBUG)
	end
end

-- Safe require helper
function M.safe_require(module)
	local ok, result = pcall(require, module)
	if not ok then
		M.debug_log("Failed to require module: " .. module)
		return nil
	end
	return result
end

-- Format path for display
function M.format_path(path, shorten)
	if shorten then
		return vim.fn.fnamemodify(path, ":~:.")
	end
	return path
end

-- Check if a path exists
function M.path_exists(path)
	return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

-- Get relative path from current working directory
function M.get_relative_path(path)
	local cwd = vim.fn.getcwd()
	local rel_path = vim.fn.fnamemodify(path, ":.")
	return rel_path ~= path and rel_path or path
end

return M
