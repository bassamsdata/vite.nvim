local M = {}
local fn = vim.fn

local function measure(name, func)
	local start = vim.uv.hrtime()
	local result = { func() } -- Capture all return values in a table
	local duration = (vim.uv.hrtime() - start) / 1000000
	vim.notify(string.format("History: %s took %.2fms", name, duration))
	return unpack(result) -- Return all values
end

-- Get base directory path
local function get_base_dir()
	return fn.stdpath("data") .. "/vite"
end

-- Generate consistent hash for project path
local function hash_path(path)
	local hash = 5381
	for i = 1, #path do
		hash = (hash * 33 + path:byte(i)) % 0x100000000
	end
	return string.format("%08x", hash)
end

-- Get project root and history file path
-- Measure project root detection
local path_cache = {}
local function initialize_project_paths(state, config)
	local cwd = fn.getcwd()

	-- Use cached paths if available
	if path_cache[cwd] then
		state.current_project_root = path_cache[cwd].root
		state.history_file_path = path_cache[cwd].history_path
		return
	end

	-- Detect project root
	state.current_project_root = vim.fs.root(0, config.project.markers)

	-- Set history file path
	local base_dir = get_base_dir()
	if state.current_project_root then
		local project_hash = hash_path(state.current_project_root)
		state.history_file_path = string.format("%s/%s.json", base_dir, project_hash)
	else
		state.history_file_path = base_dir .. "/global.json"
	end

	-- Cache the result
	path_cache[cwd] = {
		root = state.current_project_root,
		history_path = state.history_file_path,
	}
end

-- Load history from file (only when needed)
local function load_history_file(state)
	if not state.history_file_path then
		return
	end

	local file = io.open(state.history_file_path, "r")
	if not file then
		return
	end

	local content = file:read("*all")
	file:close()

	if content and content ~= "" then
		local ok, data = pcall(vim.json.decode, content)
		if ok then
			state.buffer_history = data
		end
	end
end

-- Save history to file
function M.save_to_file(state)
	if not state.history_file_path then
		return
	end

	-- Ensure directory exists before saving
	local base_dir = get_base_dir()
	if fn.isdirectory(base_dir) == 0 then
		fn.mkdir(base_dir, "p")
	end
	-- Create a temporary file path
	local temp_file = state.history_file_path .. ".tmp"

	-- Debug: Check buffer_history content
	if vim.g.vite_debug then
		vim.notify("Saving buffer history: " .. vim.inspect(state.buffer_history), vim.log.levels.DEBUG)
	end

	-- First write to temporary file
	local temp_handle = io.open(temp_file, "w")
	if not temp_handle then
		return
	end

	local ok, encoded = pcall(vim.json.encode, state.buffer_history)
	if not ok then
		temp_handle:close()
		os.remove(temp_file)
		return
	end

	local write_ok, write_err = temp_handle:write(encoded)
	temp_handle:flush()
	temp_handle:close()

	if not write_ok then
		vim.notify("Failed to write temporary file: " .. tostring(write_err), vim.log.levels.ERROR)
		os.remove(temp_file)
		return
	end

	-- Atomically rename temporary file to target file
	local rename_ok, rename_err = os.rename(temp_file, state.history_file_path)
	if not rename_ok then
		vim.notify("Failed to rename temporary file: " .. tostring(rename_err), vim.log.levels.ERROR)
		os.remove(temp_file)
		return
	end

	if vim.g.vite_debug then
		vim.notify("Successfully saved history to " .. state.history_file_path, vim.log.levels.DEBUG)
	end
end

-- Cleanup old project histories
function M.cleanup_old_histories(config)
	local base_dir = get_base_dir()
	local files = fn.glob(base_dir .. "/*.json", 0, 1)

	if #files > config.project.max_histories then
		-- Sort files by access time
		table.sort(files, function(a, b)
			return fn.getftime(a) > fn.getftime(b)
		end)

		-- Remove oldest files
		for i = config.project.max_histories + 1, #files do
			fn.delete(files[i])
		end
	end
end

-- Reset buffer score
function M.reset_score(file_path, state)
	if state.buffer_history[file_path] then
		state.buffer_history[file_path] = {
			count = 0,
			last_access = 0,
			total_score = 0,
		}
		M.save_to_file(state)
		return true
	end
	return false
end

-- Initialize history system
function M.initialize(state, config)
	initialize_project_paths(state, config)
	load_history_file(state)
end

return M
