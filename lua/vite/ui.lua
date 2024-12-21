local M = {}

local api = vim.api
local fn = vim.fn
local scoring = require("vite.scoring")

-- Add icon support function
local function get_file_icon(file_path, config)
	if not config.use_icons then
		return "", nil
	end

	local icon, hl = "", nil

	if config.icon_provider == "mini" then
		local ok, MiniIcons = pcall(require, "mini.icons")
		if ok then
			icon, hl = MiniIcons.get("file", file_path)
		end
	else
		local ok, devicons = pcall(require, "nvim-web-devicons")
		if ok then
			icon, hl = devicons.get_icon(file_path, file_path:match("^.+%.(%w+)$"), { default = true })
		end
	end

	return icon and (icon .. " ") or "", hl
end

-- Create and show the floating window
local function create_float_win(config)
	local width = config.window.width
	local height = config.window.height

	-- Calculate position
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Create buffer for the window
	local buf = api.nvim_create_buf(false, true)

	-- Window options
	local win_opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = config.window.border,
	}

	-- Create window
	local win = api.nvim_open_win(buf, true, win_opts)

	-- Add padding at the top
	api.nvim_buf_set_lines(buf, 0, 1, false, { "" })
	api.nvim_set_option_value("winblend", 0, { win = win })

	return buf, win
end

-- Display buffer list with key hints
local function display_buffers(buf, buffers, current_buf, config)
	local lines = {}
	local key_map = {}
	local highlights = {}
	local current_line = nil

	local arrow_ns = api.nvim_create_namespace("vite_arrow")
	-- Clear existing highlights
	api.nvim_buf_clear_namespace(buf, -1, 0, -1)
	api.nvim_buf_clear_namespace(buf, arrow_ns, 0, -1)

	-- Add initial empty line for top padding
	table.insert(lines, "")

	for i, buffer in ipairs(buffers) do
		local key = i <= #config.keys and config.keys[i] or tostring(i)
		local modified = buffer.modified and config.modified_icon or ""
		local is_current = buffer.id == current_buf
		local icon, icon_hl = get_file_icon(buffer.path, config)

		-- Split the path into filename and directory
		local filename = fn.fnamemodify(buffer.path, ":t")
		local dir_path = fn.fnamemodify(buffer.path, ":~:.:h")
		dir_path = dir_path == "." and " . ./" or " . " .. dir_path .. "/"
		local score_display = config.show_scores and string.format(" [" .. config.score_format .. "]", buffer.score)
			or ""

		local display_line = string.format(
			"  %s%s %s%s%s%s%s %s", -- Note the two spaces at start for arrow
			config.window.left_padding,
			key,
			icon,
			filename,
			dir_path,
			score_display,
			modified ~= "" and " " or "",
			modified
		)

		table.insert(lines, display_line)
		key_map[key] = buffer.id

		if is_current then
			current_line = i + 1
		end

		-- Calculate positions for highlights
		local base_col = #config.window.left_padding + 2
		local key_end = base_col + #key
		local icon_start = key_end + 1
		local icon_end = icon_start + #icon
		local filename_start = icon_end
		local filename_end = filename_start + #filename
		local dir_start = filename_end
		local dir_end = dir_start + #dir_path
		local score_start = dir_end
		local score_end = score_start + #score_display
		local modified_start = score_end + (#modified > 0 and 1 or 0)
		local modified_end = modified_start + #modified

		local line_idx = i + 1 - 1 -- Adjust for 0-based index

		-- Key highlight (a-g letters on the left)
		-- Uses "CursorLineNr" - typically yellow/gold color
		table.insert(highlights, {
			line = line_idx,
			hl_group = "CursorLineNr",
			start_col = base_col,
			end_col = key_end,
		})

		if icon_hl then
			table.insert(highlights, {
				line = line_idx,
				hl_group = icon_hl,
				start_col = icon_start,
				end_col = icon_end,
			})
		end

		-- Directory path highlight (the path after filename)
		-- Uses "Comment" - typically gray color
		table.insert(highlights, {
			line = line_idx,
			hl_group = "Comment",
			start_col = dir_start,
			end_col = dir_end,
		})

		-- Score display highlight (the [score] if enabled)
		-- Uses "Special" - typically purple/blue color
		if #score_display > 0 then
			table.insert(highlights, {
				line = line_idx,
				hl_group = "Special",
				start_col = score_start,
				end_col = score_end,
			})
		end

		-- Modified icon highlight (the icon showing if buffer is modified)
		-- Uses "Special" - typically purple/blue color
		if #modified > 0 then
			table.insert(highlights, {
				line = line_idx,
				hl_group = "Special",
				start_col = modified_start,
				end_col = modified_end,
			})
		end

		-- Current buffer filename highlight
		-- Uses "Title" - typically bright/bold color
		if is_current then
			table.insert(highlights, {
				line = line_idx,
				hl_group = "Title",
				start_col = filename_start,
				end_col = filename_end,
			})
		end
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Apply all highlights
	for _, hl in ipairs(highlights) do
		api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.start_col, hl.end_col)
	end

	return key_map, buffers, current_line
end

local function update_arrow(buf, prev_line, new_line, config)
	local arrow_ns = api.nvim_create_namespace("vite_arrow")

	-- Clear previous arrow
	if prev_line then
		api.nvim_buf_clear_namespace(buf, arrow_ns, prev_line - 1, prev_line)
	end

	-- Set new arrow
	if new_line > 0 then
		api.nvim_buf_set_extmark(buf, arrow_ns, new_line - 1, 0, {
			virt_text = { { config.ui.arrow_icon, "Special" } },
			virt_text_pos = "overlay",
			priority = 100,
		})
	end
end

-- Show help window
local function show_help_window(main_win, config)
	local help_text = {
		"Keymaps:",
		"a-g      - Quick select buffers",
		"q/Esc    - Close switcher",
		"g?       - Show this help",
    -- stylua: ignore start 
		config.select_key ..                "     - Select buffer               ",
		config.split_commands.vertical ..   "        - Toggle vertical split mode  ",
		config.split_commands.horizontal .. "        - Toggle horizontal split mode",
		config.delete_key ..                "        - Delete buffer               ",
		config.reset_key ..                 "        - Reset buffer frecency score ",
		-- stylua: ignore end
	}

	local width = 40
	local height = #help_text
	local main_config = api.nvim_win_get_config(main_win)

	local row = main_config.row + api.nvim_win_get_height(main_win) + 1
	local col = main_config.col

	local buf = api.nvim_create_buf(false, true)
	local win_opts = {
		relative = "editor",
		row = row + 1,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	}

	local win = api.nvim_open_win(buf, false, win_opts)
	api.nvim_buf_set_lines(buf, 0, -1, false, help_text)

	-- Add highlighting
	for i = 0, #help_text - 1 do
		if i == 0 then
			api.nvim_buf_add_highlight(buf, -1, "Title", i, 0, -1)
		else
			local dash_pos = help_text[i + 1]:find("-")
			if dash_pos then
				api.nvim_buf_add_highlight(buf, -1, "Special", i, 0, dash_pos - 1)
			end
		end
	end

	return buf, win
end

-- Set up keymaps for the switcher window
local function setup_keymaps(buf, win, state, config, key_map, mode)
	local function clear_echo()
		api.nvim_echo({ { "" } }, false, {})
	end

	-- Handle buffer selection
	local function select_buffer(buffer_id)
		clear_echo()
		api.nvim_win_close(win, true)
		-- Reset split mode flags
		mode.vertical = false
		mode.horizontal = false
		-- If we stored a next_buffer (because we deleted the original), use it
		if state.next_buffer then
			api.nvim_set_current_buf(state.next_buffer)
			state.next_buffer = nil -- Clear it after use
		else
			if mode.vertical then
				vim.cmd("vsplit")
			elseif mode.horizontal then
				vim.cmd("split")
			end
			api.nvim_set_current_buf(buffer_id)
		end
	end

	-- Set up key mappings for selection
	for key, buffer_id in pairs(key_map) do
		api.nvim_buf_set_keymap(buf, "n", key, "", {
			callback = function()
				select_buffer(buffer_id)
			end,
			noremap = true,
			silent = true,
		})
	end

	-- Add other keymaps
	local keymap_definitions = {
		[config.delete_key] = function()
			local cursor = api.nvim_win_get_cursor(win)
			local line_num = cursor[1] - 1
			local buffers = scoring.get_sorted_buffers(state)
			if line_num <= #buffers then
				local buffer_to_delete = buffers[line_num].id
				local utils = require("vite.utils")
				if utils.delete_buffer(buffer_to_delete, win) then
					vim.schedule(function()
						local new_buffers = scoring.get_sorted_buffers(state)
						if #new_buffers == 0 then
							api.nvim_win_close(win, true)
						else
							local new_key_map, _, _ =
								display_buffers(buf, new_buffers, api.nvim_get_current_buf(), config)
							setup_keymaps(buf, win, state, config, new_key_map, mode)
						end
					end)
				end
			end
		end,
		[config.reset_key] = function()
			local cursor = api.nvim_win_get_cursor(win)
			local line_num = cursor[1] - 1
			local buffers = scoring.get_sorted_buffers(state)
			if line_num <= #buffers then
				local buffer = buffers[line_num]
				local history = require("vite.history")
				if history.reset_score(buffer.path, state) then
					-- Force immediate refresh
					vim.schedule(function()
						-- Get fresh list of buffers
						local new_buffers = scoring.get_sorted_buffers(state)
						-- Redisplay buffers
						local new_key_map, _, new_current_line =
							display_buffers(buf, new_buffers, api.nvim_get_current_buf(), config)
						-- Update keymap
						setup_keymaps(buf, win, state, config, new_key_map, mode)
					end)
				end
			end
		end,
		[config.select_key] = function()
			local cursor = api.nvim_win_get_cursor(win)
			local line_num = cursor[1] - 1
			local buffers = scoring.get_sorted_buffers(state)
			if line_num <= #buffers then
				local buffer_id = buffers[line_num].id
				clear_echo() -- Clear any echo message
				api.nvim_win_close(win, true)
				if mode.vertical then
					vim.cmd("vsplit")
				elseif mode.horizontal then
					vim.cmd("split")
				end
				api.nvim_set_current_buf(buffer_id)
			end
		end,
		[config.split_commands.vertical] = function()
			mode.vertical = not mode.vertical
			mode.horizontal = false
			if mode.vertical then
				api.nvim_echo({ { " VERTICAL ", "IncSearch" } }, false, {})
			else
				clear_echo()
			end
		end,
		[config.split_commands.horizontal] = function()
			mode.horizontal = not mode.horizontal
			mode.vertical = false
			if mode.horizontal then
				api.nvim_echo({ { " HORIZONTAL ", "IncSearch" } }, false, {})
			else
				clear_echo()
			end
		end,
		["g?"] = function()
			show_help_window(win, config)
		end,
		["q"] = function()
			clear_echo()
			api.nvim_win_close(win, true)
		end,
		["<Esc>"] = function()
			mode.vertical = false
			mode.horizontal = false
			clear_echo()
			api.nvim_win_close(win, true)
		end,
	}

	for key, callback in pairs(keymap_definitions) do
		if key then
			api.nvim_buf_set_keymap(buf, "n", key, "", {
				callback = callback,
				noremap = true,
				silent = true,
			})
		end
	end

	-- Set up buffer selection keymaps
	for i, buffer in ipairs(scoring.get_sorted_buffers(state)) do
		if i <= #config.keys then
			local key = config.keys[i]
			api.nvim_buf_set_keymap(buf, "n", key, "", {
				callback = function()
					clear_echo()
					api.nvim_win_close(win, true)
					if mode.vertical then
						vim.cmd("vsplit")
					elseif mode.horizontal then
						vim.cmd("split")
					end
					api.nvim_set_current_buf(buffer.id)
				end,
				noremap = true,
				silent = true,
			})
		end
	end
end

local function setup_cursor_highlight()
	-- Create invisible cursor highlight
	vim.api.nvim_set_hl(0, "ViteCursor", { nocombine = true, blend = 100 })
	-- Apply the invisible cursor
	vim.opt.guicursor:append("a:ViteCursor/ViteCursor")
end

local function restore_cursor_highlight()
	-- Clear our custom highlight
	vim.cmd("highlight clear ViteCursor")
	-- Remove our cursor setting
	vim.schedule(function()
		vim.opt.guicursor:remove("a:ViteCursor/ViteCursor")
	end)
end

-- Main function to show buffer switcher
function M.show_switcher(state, config)
	state.original_buffer = api.nvim_get_current_buf()
	local current_buffer = api.nvim_get_current_buf()
	local buffers = scoring.get_sorted_buffers(state)
	local buf, win = create_float_win(config)
	local current_arrow_line = nil

	-- Add arrow indicator at the start of each line
	local ns_id = api.nvim_create_namespace("vite_arrow")
	-- Hide cursor if configured
	if config.ui.hide_cursor then
		setup_cursor_highlight()
	end
	local mode = { vertical = false, horizontal = false }

	-- Update arrow position when cursor moves
	api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		callback = function()
			local cursor = api.nvim_win_get_cursor(win)
			local line = cursor[1] - 1 -- 0-based line number

			-- Clear all arrows
			api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
			-- Add arrow at current line
			if line >= 0 then
				api.nvim_buf_set_extmark(buf, ns_id, line, 0, {
					virt_text = { { config.ui.arrow_icon or "→ ", "Special" } },
					virt_text_pos = "overlay",
					priority = 100,
				})
			end
		end,
	})
	-- Restore cursor when leaving buffer
	api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		desc = "Restore Cursor",
		once = true,
		callback = function()
			restore_cursor_highlight()
		end,
	})

	local key_map, buffer_list, current_line = display_buffers(buf, buffers, current_buffer, config)
	setup_keymaps(buf, win, state, config, key_map, mode) -- Fixed argument order

	-- Set initial arrow position
	if current_line then
		vim.schedule(function()
			if api.nvim_win_is_valid(win) then
				api.nvim_win_set_cursor(win, { current_line, 3 }) -- Position after arrow
				update_arrow(buf, nil, current_line, config)
				current_arrow_line = current_line
			end
		end)
	end
	-- Cleanup when closing
	api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		callback = function()
			if config.ui.hide_cursor then
				api.nvim_set_option_value("guicursor", vim.o.guicursor, { scope = "global" })
			end
		end,
		once = true,
	})

	return buf, win
end

return M
