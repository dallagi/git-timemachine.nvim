local M = {}

function M.setup(_)
	-- allow user config in the future
end

function M.toggle()
	if view.is_active() then
		view.close()
	else
		local filepath = vim.api.nvim_buf_get_name(0)
		if filepath == "" then
			print("Buffer has no file path")
			return
		end
		-- Ideally, check if file is git tracked?
		-- get_history handles it (returns empty list if not tracked usually, or errors)
		view.start(filepath)
	end
end

return M
