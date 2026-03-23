local M = {}

--- Generate a unique temporary filename
---@param temp_dir string Directory for temp file
---@return string filepath Full path to temp file
function M.get_temp_filepath(temp_dir)
  local filename = "easy_screenshot_" .. os.time() .. "_" .. math.random(1000, 9999) .. ".png"
  return temp_dir .. "/" .. filename
end

--- Check if a file exists
---@param filepath string
---@return boolean
function M.file_exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil and stat.type == "file"
end

--- Delete a file
---@param filepath string
function M.delete_file(filepath)
  vim.loop.fs_unlink(filepath)
end

--- Execute a shell command asynchronously
---@param cmd string Command to execute
---@param args table|nil Arguments
---@param callback function Callback(exit_code, stdout, stderr)
function M.execute_async(cmd, args, callback)
  args = args or {}
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local stdout_chunks = {}
  local stderr_chunks = {}

  local handle, pid
  handle, pid = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(exit_code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    handle:close()

    local stdout_data = table.concat(stdout_chunks, "")
    local stderr_data = table.concat(stderr_chunks, "")

    vim.schedule(function()
      callback(exit_code, stdout_data, stderr_data)
    end)
  end)

  if not handle then
    callback(1, "", "Failed to spawn process: " .. tostring(pid))
    return
  end

  stdout:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify("stdout read error: " .. err, vim.log.levels.ERROR)
      end)
    end
    if data then
      table.insert(stdout_chunks, data)
    end
  end)

  stderr:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify("stderr read error: " .. err, vim.log.levels.ERROR)
      end)
    end
    if data then
      table.insert(stderr_chunks, data)
    end
  end)
end

--- On WSL, relocate a file from the Windows filesystem (/mnt/...) to the Linux
--- filesystem so that downstream tools only deal with standard POSIX paths.
--- Uses Lua io for the copy because vim.loop.fs_copyfile can fail across the
--- 9P filesystem boundary between /mnt/c and the native Linux filesystem.
---@param filepath string Original file path
---@return string relocated Relocated path (unchanged on non-WSL or failure)
local function relocate_from_windows_fs(filepath)
  if vim.fn.has "wsl" ~= 1 or not filepath:match "^/mnt/" then
    return filepath
  end
  local linux_dir = (os.getenv "TMPDIR" or "/tmp") .. "/easy-screenshot"
  vim.fn.mkdir(linux_dir, "p")
  local basename = vim.fn.fnamemodify(filepath, ":t")
  local linux_path = linux_dir .. "/" .. basename

  -- Read/write via Lua io (reliable across WSL mount boundaries)
  local src = io.open(filepath, "rb")
  if not src then
    return filepath
  end
  local data = src:read "*a"
  src:close()
  if not data or #data == 0 then
    return filepath
  end

  local dst = io.open(linux_path, "wb")
  if not dst then
    return filepath
  end
  dst:write(data)
  dst:close()

  os.remove(filepath)
  return linux_path
end

--- Paste screenshot using img-clip.nvim
---@param temp_filepath string Path to temporary screenshot file
---@param imgclip_opts table|nil Options to pass to img-clip (dir_path, file_name, extension, etc.)
---@param callback function Callback(success, result)
function M.paste_with_imgclip(temp_filepath, imgclip_opts, callback)
  -- Check if img-clip is available
  local ok, imgclip = pcall(require, "img-clip")
  if not ok then
    callback(false, "img-clip.nvim not found. Please install it as a dependency.")
    return
  end

  -- On WSL the screenshot is captured by PowerShell onto the Windows filesystem
  -- (e.g. /mnt/c/tmp/...).  Move it to the Linux filesystem first so that
  -- img-clip can process it with normal POSIX file operations — no need to
  -- patch img-clip for WSL/Windows path handling.
  local filepath = relocate_from_windows_fs(temp_filepath)

  -- On WSL, img-clip's fs.copy_file shells out via powershell.exe, which
  -- cannot resolve Linux-native paths.  Temporarily monkey-patch the function
  -- with a pure-Lua implementation so that the copy succeeds without modifying
  -- img-clip's source.
  local img_fs = require "img-clip.fs"
  local orig_copy_file = img_fs.copy_file
  if vim.fn.has "wsl" == 1 then
    img_fs.copy_file = function(src, dest)
      local src_fh = io.open(src, "rb")
      if not src_fh then
        return nil, 1
      end
      local data = src_fh:read "*a"
      src_fh:close()
      local dst_fh = io.open(dest, "wb")
      if not dst_fh then
        return nil, 1
      end
      dst_fh:write(data)
      dst_fh:close()
      return "", 0
    end
  end

  -- Pass the file path directly to img-clip instead of going through the clipboard.
  -- This avoids clipboard cross-platform issues (e.g. WSL Windows clipboard vs Linux clipboard).
  -- Force copy_images so img-clip copies the temp file to the destination before we delete it.
  local opts = vim.tbl_deep_extend("force", { copy_images = true }, imgclip_opts or {})
  local paste_ok, paste_err = pcall(function()
    imgclip.paste_image(opts, filepath)
  end)

  -- Restore original copy_file
  img_fs.copy_file = orig_copy_file

  -- Delay temp file cleanup to give img-clip time to finish any async file
  -- operations.  The file lives in /tmp so a short delay is harmless.
  vim.defer_fn(function()
    pcall(os.remove, filepath)
  end, 2000)

  if paste_ok then
    callback(true, "Screenshot pasted")
  else
    callback(false, "img-clip paste failed: " .. tostring(paste_err))
  end
end

return M
