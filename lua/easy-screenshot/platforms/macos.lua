local M = {}
local utils = require "easy-screenshot.utils"

--- Find window by process name using AppleScript
---@param process_name string Application name to find
---@param callback function Callback(success, window_id_or_error)
local function find_window_by_process(process_name, callback)
  local script = string.format(
    [[
tell application "System Events"
    set appList to every process whose name contains "%s"
    if (count of appList) > 0 then
        set targetApp to item 1 of appList
        return id of window 1 of targetApp
    end if
end tell
]],
    process_name
  )

  utils.execute_async("osascript", { "-e", script }, function(exit_code, stdout, stderr)
    if exit_code == 0 and stdout ~= "" then
      local window_id = stdout:gsub("%s+", "")
      callback(true, window_id)
    else
      callback(false, "No window found for process: " .. process_name)
    end
  end)
end

--- Capture screenshot using screencapture
---@param opts table Options
---@param callback function Callback(success, filepath_or_error)
function M.capture(opts, callback)
  -- Ensure temp directory exists
  vim.fn.mkdir(opts.temp_dir, "p")
  local temp_file = utils.get_temp_filepath(opts.temp_dir)

  -- Delay before capture
  vim.defer_fn(function()
    local do_capture = function(window_opts)
      local args = { "-x" } -- Disable sound

      if window_opts and window_opts.window_id then
        -- Capture specific window by ID
        table.insert(args, "-l")
        table.insert(args, window_opts.window_id)
      else
        -- Capture active window
        table.insert(args, "-o") -- Only capture window, not shadow
        table.insert(args, "-w") -- Capture window mode (interactive, but will capture focused)
      end

      table.insert(args, temp_file)

      utils.execute_async("screencapture", args, function(exit_code, stdout, stderr)
        if exit_code == 0 and utils.file_exists(temp_file) then
          callback(true, temp_file)
        else
          callback(false, "screencapture failed: " .. stderr)
        end
      end)
    end

    -- Check if process filtering is requested
    if opts.process then
      find_window_by_process(opts.process, function(success, result)
        if success then
          do_capture { window_id = result }
        else
          callback(false, result)
        end
      end)
    else
      do_capture()
    end
  end, math.floor(opts.capture_delay * 1000))
end

--- Copy image to clipboard using osascript
---@param filepath string Path to image
---@param callback function Callback(success, error_msg)
function M.copy_to_clipboard(filepath, callback)
  -- Convert to absolute path
  local abs_path = vim.fn.fnamemodify(filepath, ":p")

  local script = string.format(
    [[
set the clipboard to (read (POSIX file "%s") as «class PNGf»)
]],
    abs_path
  )

  utils.execute_async("osascript", { "-e", script }, function(exit_code, stdout, stderr)
    if exit_code == 0 then
      callback(true)
    else
      callback(false, "Failed to copy to clipboard: " .. stderr)
    end
  end)
end

--- Check tool availability for health check
---@return table Health check results
function M.check_health()
  local health = {}

  -- Check screencapture (built-in on macOS)
  local has_screencapture = vim.fn.executable "screencapture" == 1
  table.insert(health, {
    ok = has_screencapture,
    msg = has_screencapture and "screencapture available (built-in)"
      or "screencapture not found (should be built-in on macOS)",
  })

  -- Check osascript (built-in on macOS)
  local has_osascript = vim.fn.executable "osascript" == 1
  table.insert(health, {
    ok = has_osascript,
    msg = has_osascript and "osascript available (built-in)" or "osascript not found (should be built-in on macOS)",
  })

  return health
end

return M
