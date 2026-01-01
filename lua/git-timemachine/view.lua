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

---@type State|nil
M.state = nil

function M.is_active()
  return M.state ~= nil
end

function M.close()
  if M.state and api.nvim_buf_is_valid(M.state.buffer) then
    api.nvim_buf_delete(M.state.buffer, { force = true })
  end
  M.state = nil
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
    end
  })

  return buf
end

function M.update_view()
  if not M.state then return end
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
  print(string.format("[%d/%d] %s: %s (%s)", 
    M.state.index, #M.state.revisions, 
    revision.short_hash, revision.subject, revision.date))
end

function M.prev_revision()
  if not M.state then return end
  if M.state.index < #M.state.revisions then
    M.state.index = M.state.index + 1
    M.update_view()
  else
    print("No older revisions")
  end
end

function M.next_revision()
  if not M.state then return end
  if M.state.index > 1 then
    M.state.index = M.state.index - 1
    M.update_view()
  else
    print("No newer revisions")
  end
end

function M.show_commit_info()
  if not M.state then return end
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
    title_pos = "center"
  })
  
  -- Close mapping
  vim.keymap.set("n", "q", function() api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() api.nvim_win_close(win, true) end, { buffer = buf })
end

function M.start(filepath)
  if M.is_active() then M.close() end
  
  local revisions = git.get_history(filepath)
  if #revisions == 0 then
    print("No git history found for " .. filepath)
    return
  end

  local original_buf = api.nvim_get_current_buf()
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
    filetype = filetype
  }
  
  M.update_view()
end

return M
