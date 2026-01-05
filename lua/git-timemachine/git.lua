local M = {}

---@class DiffHunk
---@field a_start integer
---@field a_count integer
---@field b_start integer
---@field b_count integer

---@class Revision
---@field hash string Full commit hash
---@field short_hash string Short commit hash
---@field subject string Commit subject
---@field date string Relative date

---Execute a git command and return the output
---@param args string[]
---@return string? stdout
---@return string? stderr
local function git_exec(args)
	local obj = vim.system(vim.tbl_flatten({ "git", args }), { text = true }):wait()
	if obj.code ~= 0 then
		return nil, obj.stderr
	end
	return obj.stdout, nil
end

local function get_repo_root()
	local root_obj = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
	if root_obj.code ~= 0 then
		return nil
	end
	return root_obj.stdout:gsub("\n", "")
end

local function get_rel_path(filepath)
	local root = get_repo_root()
	if not root then
		return filepath
	end
	if filepath:sub(1, #root) == root then
		return filepath:sub(#root + 2)
	end
	return filepath
end

---Get git history for a file
---@param filepath string
---@return Revision[]
function M.get_history(filepath)
	-- Format: hash short_hash date | subject
	-- Using a custom delimiter | to separate fields safely (assuming subject might contain spaces)
	-- %H: commit hash
	-- %h: abbreviated commit hash
	-- %cr: committer date, relative
	-- %s: subject
	local format = "%H\t%h\t%cr\t%s"
	local stdout, _ = git_exec({ "log", "--pretty=format:" .. format, "--", filepath })

	if not stdout then
		return {}
	end

	local history = {}
	for line in stdout:gmatch("[^\r\n]+") do
		local hash, short_hash, date, subject = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)")
		if hash then
			table.insert(history, {
				hash = hash,
				short_hash = short_hash,
				date = date,
				subject = subject,
			})
		end
	end
	return history
end

---Get file content at a specific revision
---@param hash string
---@param filepath string
---@return string[]? lines
function M.show_file(hash, filepath)
	-- git show hash:filepath
	-- Note: filepath needs to be relative to the git root for git show usually,
	-- or we rely on git to figure it out depending on CWD.
	-- To be safe, we might need to get the relative path or run from root.
	-- For now, let's assume git handles absolute paths if we are in the repo, or we strip it.
	-- Actually `git show hash:absolute_path` often fails.
	-- We should get the relative path relative to the git root.

	-- Assuming CWD is inside the repo, we can try using the path as is or `cat-file -p` or similar?
	-- Simplest is `git show hash:./relative_path` or similar.
	-- Let's stick to `git show hash:path` and see if `git` complains about absolute.
	-- If it does, we'll need to resolve relative path.

	-- Better approach: `git show <hash>:<path>` works if path is relative to root.
	-- We can use `git ls-files --full-name <path>` to get the path relative to root?
	-- Or just `git show <hash> -- <path>` ?
	-- `git show` with `--` shows the log/diff usually.
	-- `git show <hash>:<path>` is the blob content.

	-- Let's try to get the relative path first.
	local rel_path = get_rel_path(filepath)

	local stdout, _ = git_exec({ "show", hash .. ":" .. rel_path })
	if not stdout then
		-- Fallback or error handling
		return nil
	end

	return vim.split(stdout, "\n", { plain = true })
end

---Get detailed commit info
---@param hash string
---@return string[]? lines
function M.show_info(hash)
	local stdout, _ = git_exec({ "show", hash, "--stat", "--patch" })
	if not stdout then
		return nil
	end
	return vim.split(stdout, "\n", { plain = true })
end

---@param a_rev string|nil
---@param b_rev string|nil
---@param filepath string
---@return DiffHunk[]
function M.get_diff_hunks(a_rev, b_rev, filepath)
	local rel_path = get_rel_path(filepath)
	local args = { "diff", "--no-color", "--unified=0" }
	if a_rev and b_rev then
		table.insert(args, a_rev)
		table.insert(args, b_rev)
	elseif a_rev then
		table.insert(args, a_rev)
	end
	table.insert(args, "--")
	table.insert(args, rel_path)

	local stdout, _ = git_exec(args)
	if not stdout then
		return {}
	end

	local hunks = {}
	for line in stdout:gmatch("[^\r\n]+") do
		local a_start, a_count, b_start, b_count = line:match("^@@%s%-(%d+),?(%d*)%s%+(%d+),?(%d*)%s@@")
		if a_start then
			local a_num = tonumber(a_start)
			local a_len = tonumber(a_count) or 1
			local b_num = tonumber(b_start)
			local b_len = tonumber(b_count) or 1
			table.insert(hunks, {
				a_start = a_num,
				a_count = a_len,
				b_start = b_num,
				b_count = b_len,
			})
		end
	end

	return hunks
end

return M
