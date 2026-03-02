local M = {}
local view = require("git-timemachine.view")

function M.toggle()
	if view.is_active() then
		view.close()
	else
		local filepath = vim.api.nvim_buf_get_name(0)
		if filepath == "" then
			print("Buffer has no file path")
			return
		end
		view.start(filepath)
	end
end

return M
