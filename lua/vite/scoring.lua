local M = {}

local api = vim.api
-- Store config locally in the module
local config

function M.initialize(cfg)
	config = cfg
end

-- Calculate frecency score
-- Combines frequency (how often) and recency (how recent) of buffer access
function M.calculate_score(file_path, state)
	if type(file_path) ~= "string" or file_path == "" then
		return 0
	end

	local history = state.buffer_history[file_path] or {
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

-- Check if buffer is valid for scoring
function M.is_valid_buffer(buf)
	-- Check if buffer is valid and listed
	if not api.nvim_buf_is_valid(buf) or not api.nvim_get_option_value("buflisted", { buf = buf }) then
		return false
	end

	local file_path = api.nvim_buf_get_name(buf)
	if file_path == "" then
		return false
	end

	-- Check if it's a real file (not a terminal, help, etc)
	local buftype = api.nvim_get_option_value("buftype", { buf = buf })
	if buftype ~= "" then
		return false
	end

	return true
end

-- Update buffer access history
function M.update_history(buf_id, state)
	local file_path = api.nvim_buf_get_name(buf_id)
	if file_path == "" then -- Skip unnamed buffers
		return
	end

	if not state.buffer_history[file_path] then
		state.buffer_history[file_path] = {
			count = 0,
			last_access = 0,
			total_score = 0,
		}
	end

	-- Update access data and calculate new score
	state.buffer_history[file_path].count = state.buffer_history[file_path].count + 1
	state.buffer_history[file_path].last_access = os.time()
	-- Calculate and cache the score
	state.buffer_history[file_path].total_score = M.calculate_score(file_path, state)

	if vim.g.vite_debug then
		vim.notify(
			string.format(
				"Updated history for %s:\n" .. "  Count: %d\n" .. "  Score: %.4f",
				file_path,
				state.buffer_history[file_path].count,
				state.buffer_history[file_path].total_score
			),
			vim.log.levels.DEBUG
		)
	end
end

-- Get sorted list of buffers based on frecency
function M.get_sorted_buffers(state)
	local buffers = {}

	for _, buf in ipairs(api.nvim_list_bufs()) do
		if M.is_valid_buffer(buf) then
			local file_path = api.nvim_buf_get_name(buf)
			-- Use cached score or 0 for new buffers
			local score = state.buffer_history[file_path] and state.buffer_history[file_path].total_score or 0

			table.insert(buffers, {
				id = buf,
				path = file_path,
				score = score,
				name = vim.fn.fnamemodify(file_path, ":~:."),
				modified = api.nvim_get_option_value("modified", { buf = buf }),
			})
		end
	end

	-- Sort by cached frecency score
	table.sort(buffers, function(a, b)
		return a.score > b.score
	end)

	if vim.g.vite_debug then
		vim.notify("Sorted buffers scores:", vim.log.levels.DEBUG)
		for _, buf in ipairs(buffers) do
			vim.notify(string.format("  %s: %.4f", buf.name, buf.score), vim.log.levels.DEBUG)
		end
	end

	return buffers
end

return M
