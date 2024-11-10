local M

local api = vim.api
local fn = vim.fn

-- Add window tracking
M.current_switcher = {
	buf = nil,
	win = nil,
}
local config = {
	scoring = {
		-- Weights should add up to 1.0
		frequency_weight = 0.4, -- Default weight for frequency (how often)
		recency_weight = 0.6, -- Default weight for recency (how recent)
		-- Controls how quickly recency score decays
		-- Higher values = slower decay = longer-lasting recency impact
		recency_decay = 1.0,
	},
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

-- Calculate frecency score
-- Combines frequency (how often) and recency (how recent) of buffer access
local function calculate_frecency(file_path)
	if type(file_path) ~= "string" or file_path == "" then
		return 0
	end

	local history = buffer_history[file_path] or {
		count = 0,
		last_access = os.time(),
		total_score = 0,
	}
	local current_time = os.time()
	local time_diff = math.max(current_time - history.last_access, 1)

	-- Recency score with configurable decay
	local recency_score = 1 / (1 + math.log(time_diff) * config.scoring.recency_decay)
	-- Frequency score (capped at 100 visits)
	local frequency_score = math.min(history.count, 100)

	-- Apply weights
	return (frequency_score * config.scoring.frequency_weight) + (recency_score * config.scoring.recency_weight)
end

-- Get sorted list of buffers based on frecency
local function get_sorted_buffers()
	local buffers = {}

	-- TODO: might change this to list tabpage buffers
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if is_valid_buffer(buf) then
			local file_path = api.nvim_buf_get_name(buf)
			-- Use cached score or 0 for new buffers
			local score = buffer_history[file_path] and buffer_history[file_path].total_score or 0
			table.insert(buffers, {
				id = buf,
				path = file_path,
				score = score,
				name = fn.fnamemodify(file_path, ":~:."),
				modified = api.nvim_get_option_value("modified", { buf = buf }),
			})
		end
	end

	-- Sort by cached frecency score
	table.sort(buffers, function(a, b)
		return a.score > b.score
	end)

	if vim.g.frecency_debug then
		vim.notify("Sorted buffers scores:", vim.log.levels.DEBUG)
		for _, buf in ipairs(buffers) do
			vim.notify(string.format("  %s: %.4f", buf.name, buf.score), vim.log.levels.DEBUG)
		end
	end

	return buffers
end
return M
