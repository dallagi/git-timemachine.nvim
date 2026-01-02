local api = vim.api
local git = require("git-timemachine.git")

local M = {}

---@class State
---@field original_buf integer
---@field buffer integer
---@field revisions Revision[]
---@field index integer
---@field filepath string
---@field filetype string
---@field cursor_line integer
---@field cursor_col integer
---@field view_offset integer
---@field view_leftcol integer

---@type State|nil
M.state = nil

local function invert_hunks(hunks)
	local inverted = {}
	for _, hunk in ipairs(hunks) do
		table.insert(inverted, {
			a_start = hunk.b_start,
			a_count = hunk.b_count,
			b_start = hunk.a_start,
			b_count = hunk.a_count,
		})
	end
	table.sort(inverted, function(a, b)
		return a.a_start < b.a_start
	end)
	return inverted
end

local function map_line_with_hunks(line, hunks)
	local mapped = line
	for _, hunk in ipairs(hunks) do
		if hunk.a_count == 0 then
			if line >= hunk.a_start then
				mapped = mapped + hunk.b_count
			end
		else
			local a_end = hunk.a_start + hunk.a_count - 1
			if line < hunk.a_start then
				break
			elseif line > a_end then
				mapped = mapped + (hunk.b_count - hunk.a_count)
			else
				if hunk.b_count == 0 then
					mapped = hunk.b_start
				else
					local offset = line - hunk.a_start
					local capped = math.min(offset, hunk.b_count - 1)
					mapped = hunk.b_start + capped
				end
				break
			end
		end
	end
	return math.max(1, mapped)
end

local function capture_view_state()
	local cursor = api.nvim_win_get_cursor(0)
	local view = vim.fn.winsaveview()
	local topline = view.topline or 1
	return {
		line = cursor[1],
		col = cursor[2],
		offset = math.max(0, cursor[1] - topline),
		leftcol = view.leftcol or 0,
	}
end

local function apply_view_state(line, col, offset, leftcol)
	local buf = M.state.buffer
	local max_line = api.nvim_buf_line_count(buf)
	local clamped_line = math.max(1, math.min(line, max_line))
	local topline = math.max(1, clamped_line - (offset or 0))
	vim.fn.winrestview({
		lnum = clamped_line,
		col = math.max(0, col or 0),
		topline = topline,
		leftcol = leftcol or 0,
	})
	return clamped_line
end

function M.is_active()
	return M.state ~= nil
end

function M.close()
	if M.state and api.nvim_buf_is_valid(M.state.buffer) then
		api.nvim_buf_delete(M.state.buffer, { force = true })
	end
	M.state = nil
	vim.cmd("echo ''")
end

---Create the scratch buffer and setup keymaps
local function setup_buffer(filetype)
	local buf = api.nvim_create_buf(false, true) -- listed=false, scratch=true
	api.nvim_set_option_value("filetype", filetype, { buf = buf })
	api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	api.nvim_set_option_value("modifiable", false, { buf = buf })
	-- cursorline is window-local, set it after attaching to window

	-- Keymaps
	local opts = { noremap = true, silent = true, buffer = buf }
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<C-k>", M.prev_revision, opts)
	vim.keymap.set("n", "<C-j>", M.next_revision, opts)

	-- Auto-close if buffer is wiped externally
	api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		callback = function()
			M.state = nil
		end,
	})

	return buf
end

function M.update_view()
	if not M.state then
		error("GitTimeMachine: view called without active state")
	end
	local revision = M.state.revisions[M.state.index]

	-- Fetch content
	local content = git.show_file(revision.hash, M.state.filepath)

	local buf = M.state.buffer
	api.nvim_set_option_value("modifiable", true, { buf = buf })
	if content then
		api.nvim_buf_set_lines(buf, 0, -1, false, content)
	else
		api.nvim_buf_set_lines(buf, 0, -1, false, { "Error loading content for " .. revision.short_hash })
	end
	api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Update echo area/status
	print(
		string.format(
			"[%d/%d] %s: %s (%s)",
			M.state.index,
			#M.state.revisions,
			revision.short_hash,
			revision.subject,
			revision.date
		)
	)

	if M.state.cursor_line then
		M.state.cursor_line = apply_view_state(
			M.state.cursor_line,
			M.state.cursor_col,
			M.state.view_offset,
			M.state.view_leftcol
		)
	end
end

function M.prev_revision()
	if not M.state then
		error("GitTimeMachine: prev_revision called without active state")
	end
	if M.state.index < #M.state.revisions then
		local view_state = capture_view_state()
		M.state.cursor_line = view_state.line
		M.state.cursor_col = view_state.col
		M.state.view_offset = view_state.offset
		M.state.view_leftcol = view_state.leftcol

		local from_hash = M.state.revisions[M.state.index].hash
		M.state.index = M.state.index + 1
		local to_hash = M.state.revisions[M.state.index].hash
		local hunks = git.get_diff_hunks(from_hash, to_hash, M.state.filepath)
		M.state.cursor_line = map_line_with_hunks(M.state.cursor_line, hunks)
		M.update_view()
	else
		print("No older revisions")
	end
end

function M.next_revision()
	if not M.state then
		error("GitTimeMachine: next_revision called without active state")
	end
	if M.state.index > 1 then
		local view_state = capture_view_state()
		M.state.cursor_line = view_state.line
		M.state.cursor_col = view_state.col
		M.state.view_offset = view_state.offset
		M.state.view_leftcol = view_state.leftcol

		local from_hash = M.state.revisions[M.state.index].hash
		M.state.index = M.state.index - 1
		local to_hash = M.state.revisions[M.state.index].hash
		local hunks = git.get_diff_hunks(from_hash, to_hash, M.state.filepath)
		M.state.cursor_line = map_line_with_hunks(M.state.cursor_line, hunks)
		M.update_view()
	else
		print("No newer revisions")
	end
end

function M.show_commit_info()
	if not M.state then
		error("GitTimeMachine: show_info called without active state")
	end
	local revision = M.state.revisions[M.state.index]

	-- Native fallback
	local content = git.show_info(revision.hash)
	if not content then
		print("Failed to get commit info")
		return
	end

	local buf = api.nvim_create_buf(false, true)
	api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	api.nvim_set_option_value("filetype", "git", { buf = buf })
	api.nvim_buf_set_lines(buf, 0, -1, false, content)

	-- Calculate float size
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Commit Info: " .. revision.short_hash .. " ",
		title_pos = "center",
	})

	-- Close mapping
	vim.keymap.set("n", "q", function()
		api.nvim_win_close(win, true)
	end, { buffer = buf })
	vim.keymap.set("n", "<Esc>", function()
		api.nvim_win_close(win, true)
	end, { buffer = buf })
end

function M.start(filepath)
	if M.is_active() then
		M.close()
	end

	local revisions = git.get_history(filepath)
	if #revisions == 0 then
		print("No git history found for " .. filepath)
		return
	end

	local original_buf = api.nvim_get_current_buf()
	local original_view = capture_view_state()
	local filetype = api.nvim_get_option_value("filetype", { buf = original_buf })

	local buf = setup_buffer(filetype)
	api.nvim_set_current_buf(buf)
	api.nvim_set_option_value("cursorline", true, { scope = "local", win = 0 })

	-- Add Enter keymap
	vim.keymap.set("n", "<CR>", M.show_commit_info, { buffer = buf, noremap = true, silent = true })

	M.state = {
		original_buf = original_buf,
		buffer = buf,
		revisions = revisions,
		index = 1, -- Start at latest revision (index 1 is latest in our list usually, git log order)
		filepath = filepath,
		filetype = filetype,
		cursor_line = original_view.line,
		cursor_col = original_view.col,
		view_offset = original_view.offset,
		view_leftcol = original_view.leftcol,
	}

	local head_hunks = git.get_diff_hunks("HEAD", nil, filepath)
	if #head_hunks > 0 then
		local inverted = invert_hunks(head_hunks)
		M.state.cursor_line = map_line_with_hunks(M.state.cursor_line, inverted)
	end

	M.update_view()
end

return M
