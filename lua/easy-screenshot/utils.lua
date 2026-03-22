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

  -- Copy temp file to clipboard (platform-specific)
  local platform = require "easy-screenshot.platforms"
  platform.copy_to_clipboard(temp_filepath, function(success, error_msg)
    if not success then
      M.delete_file(temp_filepath)
      callback(false, "Failed to copy to clipboard: " .. (error_msg or "Unknown error"))
      return
    end

    -- Small delay to ensure clipboard is ready
    vim.defer_fn(function()
      -- Trigger img-clip paste with optional overrides
      local paste_ok, paste_err = pcall(function()
        if imgclip_opts and next(imgclip_opts) then
          imgclip.paste_image(imgclip_opts)
        else
          vim.cmd "PasteImage"
        end
      end)

      -- Clean up temp file
      M.delete_file(temp_filepath)

      if paste_ok then
        callback(true, "Screenshot pasted")
      else
        callback(false, "img-clip paste failed: " .. tostring(paste_err))
      end
    end, 100)
  end)
end

return M
