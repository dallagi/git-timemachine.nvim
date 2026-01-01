local M = {}

---@class Revision
---@field hash string Full commit hash
---@field short_hash string Short commit hash
---@field subject string Commit subject
---@field date string Relative date
---@field author string Author name

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

---Get git history for a file
---@param filepath string
---@return Revision[]
function M.get_history(filepath)
  -- Format: hash short_hash date | subject
  -- Using a custom delimiter | to separate fields safely (assuming subject might contain spaces)
  -- %H: commit hash
  -- %h: abbreviated commit hash
  -- %cr: committer date, relative
  -- %an: author name
  -- %s: subject
  local format = "%H\t%h\t%cr\t%an\t%s"
  local stdout, _ = git_exec({ "log", "--pretty=format:" .. format, "--", filepath })

  if not stdout then
    return {}
  end

  local history = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local hash, short_hash, date, author, subject = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)")
    if hash then
      table.insert(history, {
        hash = hash,
        short_hash = short_hash,
        date = date,
        author = author,
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
  local rel_path = filepath
  local root_obj = vim.system({"git", "rev-parse", "--show-toplevel"}, {text=true}):wait()
  if root_obj.code == 0 then
      local root = root_obj.stdout:gsub("\n", "")
      -- Simple check if filepath starts with root
      if filepath:sub(1, #root) == root then
          rel_path = filepath:sub(#root + 2) -- +2 for trailing slash and start index
      end
  end

  local stdout, stderr = git_exec({ "show", hash .. ":" .. rel_path })
  if not stdout then
    -- Fallback or error handling
    return nil
  end

  local lines = {}
  for line in stdout:gmatch("([^\r\n]*)\r?\n?") do
     table.insert(lines, line)
  end
  -- The loop above adds an empty string at the end if the file ends with newline, 
  -- or might behave slightly differently. passing lines to nvim_buf_set_lines prefers a list.
  -- vim.split is safer.
  return vim.split(stdout, "\n", { plain = true })
end

---Get detailed commit info
---@param hash string
---@return string[]? lines
function M.show_info(hash)
  local stdout, _ = git_exec({ "show", hash, "--stat", "--patch" })
  if not stdout then return nil end
  return vim.split(stdout, "\n", { plain = true })
end

return M
