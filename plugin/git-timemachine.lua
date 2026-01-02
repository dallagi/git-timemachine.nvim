require("git-timemachine")

vim.api.nvim_create_user_command("GitTimeMachine", function()
	require("git-timemachine").toggle()
end, {})
