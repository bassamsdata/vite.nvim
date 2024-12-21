local M = {}

function M.measure_load_time(module_name)
	local start = vim.uv.hrtime()
	local success, module = pcall(require, module_name)
	local end_time = vim.uv.hrtime()
	local duration = (end_time - start) / 1000000 -- Convert to milliseconds

	if success then
		vim.notify(string.format("Loading '%s' took %.2fms", module_name, duration))
		return module
	else
		vim.notify(string.format("Failed to load '%s': %s", module_name, module), vim.log.levels.ERROR)
		return nil
	end
end

return M
