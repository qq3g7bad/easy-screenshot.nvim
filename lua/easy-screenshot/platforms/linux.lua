local M = {}
local utils = require "easy-screenshot.utils"

--- Check which screenshot tools are available
---@return table Available tools
local function check_available_tools()
  local tools = {
    scrot = vim.fn.executable "scrot" == 1,
    maim = vim.fn.executable "maim" == 1,
    gnome_screenshot = vim.fn.executable "gnome-screenshot" == 1,
    import = vim.fn.executable "import" == 1, -- ImageMagick
    xdotool = vim.fn.executable "xdotool" == 1,
    wmctrl = vim.fn.executable "wmctrl" == 1,
    xprop = vim.fn.executable "xprop" == 1,
    xclip = vim.fn.executable "xclip" == 1,
    xsel = vim.fn.executable "xsel" == 1,
  }
  return tools
end

--- List all GUI windows with their process names
---@param callback function Callback(success, windows_or_error)
function M.list_windows(callback)
  local tools = check_available_tools()

  if tools.wmctrl then
    -- Use wmctrl -lp to get window list with PIDs
    utils.execute_async("wmctrl", { "-lp" }, function(exit_code, stdout, stderr)
      if exit_code ~= 0 then
        callback(false, "wmctrl failed: " .. stderr)
        return
      end

      local windows = {}
      for line in stdout:gmatch "[^\r\n]+" do
        -- Format: window_id desktop pid hostname window_title
        local win_id, desktop, pid, rest = line:match "^(0x%x+)%s+(%S+)%s+(%d+)%s+(.+)$"
        if win_id and pid then
          -- Get process name from PID
          local cmd_file = "/proc/" .. pid .. "/comm"
          local f = io.open(cmd_file, "r")
          local proc_name = "unknown"
          if f then
            proc_name = f:read "*line" or "unknown"
            f:close()
          end

          -- Extract window title (after hostname)
          local title = rest:match "%S+%s+(.+)$" or rest

          table.insert(windows, {
            id = win_id,
            pid = pid,
            process = proc_name,
            title = title,
          })
        end
      end

      callback(true, windows)
    end)
  elseif tools.xdotool and tools.xprop then
    -- Use xdotool to search all windows
    utils.execute_async("xdotool", { "search", "--onlyvisible", "--name", "." }, function(exit_code, stdout, stderr)
      if exit_code ~= 0 then
        callback(false, "xdotool failed: " .. stderr)
        return
      end

      local window_ids = {}
      for line in stdout:gmatch "[^\r\n]+" do
        table.insert(window_ids, line)
      end

      if #window_ids == 0 then
        callback(true, {})
        return
      end

      -- Get info for each window
      local windows = {}
      local processed = 0

      for _, win_id in ipairs(window_ids) do
        -- Get window name
        utils.execute_async("xdotool", { "getwindowname", win_id }, function(code, name_out, name_err)
          local title = code == 0 and name_out:gsub("%s+$", "") or "Unknown"

          -- Get PID via xprop
          utils.execute_async("xprop", { "-id", win_id, "_NET_WM_PID" }, function(pid_code, pid_out, pid_err)
            local pid = pid_out:match "_NET_WM_PID%(CARDINAL%)%s*=%s*(%d+)"
            local proc_name = "unknown"

            if pid then
              local cmd_file = "/proc/" .. pid .. "/comm"
              local f = io.open(cmd_file, "r")
              if f then
                proc_name = f:read "*line" or "unknown"
                f:close()
              end
            end

            table.insert(windows, {
              id = win_id,
              pid = pid or "unknown",
              process = proc_name,
              title = title,
            })

            processed = processed + 1
            if processed == #window_ids then
              callback(true, windows)
            end
          end)
        end)
      end
    end)
  else
    callback(false, "No window listing tool available. Install wmctrl or xdotool+xprop")
  end
end

--- Get active window ID
---@param callback function Callback(success, window_id_or_error)
local function get_active_window_id(callback)
  local tools = check_available_tools()

  if tools.xdotool then
    utils.execute_async("xdotool", { "getactivewindow" }, function(exit_code, stdout, stderr)
      if exit_code == 0 then
        local window_id_dec = stdout:gsub("%s+", "")
        -- Convert decimal to hex for compatibility with X11 tools
        local window_id_hex = string.format("0x%x", tonumber(window_id_dec))
        callback(true, window_id_hex)
      else
        callback(false, "xdotool failed: " .. stderr)
      end
    end)
  elseif tools.wmctrl then
    -- wmctrl -l shows window list, parse for active
    utils.execute_async("wmctrl", { "-lG" }, function(exit_code, stdout, stderr)
      if exit_code == 0 then
        -- Get active window from xprop
        utils.execute_async("xprop", { "-root", "_NET_ACTIVE_WINDOW" }, function(code, out, err)
          if code == 0 then
            local window_id = out:match "0x%x+"
            callback(true, window_id)
          else
            callback(false, "Failed to get active window")
          end
        end)
      else
        callback(false, "wmctrl failed: " .. stderr)
      end
    end)
  else
    callback(false, "No window manager tool available (xdotool or wmctrl)")
  end
end

--- Fallback: find window using xdotool search --class, then --name
---@param process_name string
---@param tools table
---@param callback function
local function find_window_by_process_xdotool(process_name, tools, callback)
  if not tools.xdotool then
    callback(false, "No window search tool available. Install wmctrl or xdotool.")
    return
  end

  -- Try --class first (matches WM_CLASS, usually the app name)
  utils.execute_async("xdotool", { "search", "--class", process_name }, function(exit_code, stdout, stderr)
    if exit_code == 0 and stdout ~= "" then
      local window_id_dec = stdout:match "(%d+)"
      if window_id_dec then
        local window_id_hex = string.format("0x%x", tonumber(window_id_dec))
        callback(true, window_id_hex)
        return
      end
    end

    -- Fall back to --name (matches window title)
    utils.execute_async("xdotool", { "search", "--name", process_name }, function(code2, out2, err2)
      if code2 == 0 and out2 ~= "" then
        local wid = out2:match "(%d+)"
        if wid then
          callback(true, string.format("0x%x", tonumber(wid)))
          return
        end
      end
      callback(false, "No window found for process: " .. process_name)
    end)
  end)
end

--- Find window by process name
--- Uses wmctrl + /proc/<pid>/comm to match by actual process name,
--- then falls back to xdotool search --class, then --name.
---@param process_name string Process to search for
---@param callback function Callback(success, window_id_or_error)
local function find_window_by_process(process_name, callback)
  local tools = check_available_tools()
  local pattern = process_name:lower()

  -- Strategy 1: wmctrl -lp + /proc/<pid>/comm (most reliable)
  if tools.wmctrl then
    utils.execute_async("wmctrl", { "-lp" }, function(exit_code, stdout, stderr)
      if exit_code == 0 then
        for line in stdout:gmatch "[^\r\n]+" do
          local win_id, _, pid = line:match "^(0x%x+)%s+(%S+)%s+(%d+)"
          if win_id and pid then
            local cmd_file = "/proc/" .. pid .. "/comm"
            local f = io.open(cmd_file, "r")
            if f then
              local proc = f:read "*line" or ""
              f:close()
              if proc:lower():find(pattern, 1, true) then
                callback(true, win_id)
                return
              end
            end
          end
        end
      end

      -- wmctrl didn't find it, try xdotool strategies
      find_window_by_process_xdotool(process_name, tools, callback)
    end)
    return
  end

  -- No wmctrl, go straight to xdotool
  find_window_by_process_xdotool(process_name, tools, callback)
end

--- Capture screenshot using available tool
---@param opts table Options
---@param callback function Callback(success, filepath_or_error)
function M.capture(opts, callback)
  local tools = check_available_tools()

  -- Ensure temp directory exists
  vim.fn.mkdir(opts.temp_dir, "p")
  local temp_file = utils.get_temp_filepath(opts.temp_dir)

  -- Delay before capture to allow window switching
  vim.defer_fn(function()
    local capture_window_id = function(window_id, return_focus_to)
      -- For capturing a specific window with import, we need to focus it first
      -- because import can't capture background windows reliably
      local do_capture = function()
        if tools.scrot then
          -- scrot with focused window
          utils.execute_async("scrot", { "-u", "-o", temp_file }, function(exit_code, stdout, stderr)
            if exit_code == 0 and utils.file_exists(temp_file) then
              callback(true, temp_file)
            else
              callback(false, "scrot failed: " .. stderr)
            end
          end)
        elseif tools.maim then
          -- maim with window ID (maim can capture background windows)
          local args = window_id and { "-i", window_id, temp_file } or { temp_file }
          utils.execute_async("maim", args, function(exit_code, stdout, stderr)
            if exit_code == 0 and utils.file_exists(temp_file) then
              callback(true, temp_file)
            else
              callback(false, "maim failed: " .. stderr)
            end
          end)
        elseif tools.gnome_screenshot then
          -- gnome-screenshot active window
          utils.execute_async("gnome-screenshot", { "-w", "-f", temp_file }, function(exit_code, stdout, stderr)
            if exit_code == 0 and utils.file_exists(temp_file) then
              callback(true, temp_file)
            else
              callback(false, "gnome-screenshot failed: " .. stderr)
            end
          end)
        elseif tools.import then
          -- ImageMagick import - capture currently focused window
          utils.execute_async("xprop", { "-root", "_NET_ACTIVE_WINDOW" }, function(code, out, err)
            local active_win_id = "root"
            if code == 0 then
              active_win_id = out:match "0x%x+" or "root"
            end

            utils.execute_async("import", { "-window", active_win_id, temp_file }, function(exit_code, stdout, stderr)
              if exit_code == 0 and utils.file_exists(temp_file) then
                callback(true, temp_file)
              else
                callback(false, "import failed: " .. stderr)
              end
            end)
          end)
        else
          callback(false, "No screenshot tool available. Install scrot, maim, gnome-screenshot, or ImageMagick")
        end
      end

      -- If we have a specific window ID, capture it directly with import
      -- (no need to focus-switch; import -window accepts hex X11 IDs)
      if window_id and tools.import then
        utils.execute_async("import", { "-window", window_id, temp_file }, function(exit_code, stdout, stderr)
          if exit_code == 0 and utils.file_exists(temp_file) then
            callback(true, temp_file)
          else
            callback(false, "import failed for window " .. window_id .. ": " .. stderr)
          end
        end)
      elseif window_id and tools.maim then
        -- maim can also capture by window ID (decimal)
        local dec_id = tostring(tonumber(window_id, 16) or window_id)
        utils.execute_async("maim", { "-i", dec_id, temp_file }, function(exit_code, stdout, stderr)
          if exit_code == 0 and utils.file_exists(temp_file) then
            callback(true, temp_file)
          else
            callback(false, "maim failed for window " .. window_id .. ": " .. stderr)
          end
        end)
      else
        do_capture()
      end
    end

    -- Get current window ID to return focus after capture
    local current_window_id = nil
    if tools.xdotool then
      utils.execute_async("xdotool", { "getactivewindow" }, function(code, out, err)
        if code == 0 then
          current_window_id = out:gsub("%s+", "")
        end

        -- Now determine target window and capture
        if opts.process then
          find_window_by_process(opts.process, function(success, result)
            if success then
              capture_window_id(result, current_window_id)
            else
              -- Process not found, fallback to active window with warning
              vim.schedule(function()
                vim.notify(
                  string.format("Process '%s' not found. Capturing active window instead.", opts.process),
                  vim.log.levels.WARN
                )
              end)
              vim.defer_fn(function()
                capture_window_id(nil, nil)
              end, 500)
            end
          end)
        else
          -- Capture active window
          capture_window_id(nil, nil)
        end
      end)
    else
      -- No xdotool, just capture active window
      if opts.process then
        vim.schedule(function()
          vim.notify(
            "Process filtering not available (missing xdotool). Capturing active window instead.",
            vim.log.levels.WARN
          )
        end)
      end
      capture_window_id(nil, nil)
    end
  end, math.floor(opts.capture_delay * 1000))
end

--- Copy image file to clipboard
---@param filepath string Path to image
---@param callback function Callback(success, error_msg)
function M.copy_to_clipboard(filepath, callback)
  local tools = check_available_tools()

  if tools.xclip then
    utils.execute_async("xclip", {
      "-selection",
      "clipboard",
      "-t",
      "image/png",
      "-i",
      filepath,
    }, function(exit_code, stdout, stderr)
      if exit_code == 0 then
        callback(true)
      else
        callback(false, "xclip failed: " .. stderr)
      end
    end)
  elseif tools.xsel then
    utils.execute_async("xsel", {
      "--clipboard",
      "--input",
      filepath,
    }, function(exit_code, stdout, stderr)
      if exit_code == 0 then
        callback(true)
      else
        callback(false, "xsel failed: " .. stderr)
      end
    end)
  else
    callback(false, "No clipboard tool available (xclip or xsel)")
  end
end

--- Check tool availability for health check
---@return table Health check results
function M.check_health()
  local tools = check_available_tools()
  local health = {}

  -- Screenshot tools
  local screenshot_tools = { "scrot", "maim", "gnome_screenshot", "import" }
  local has_screenshot_tool = false
  for _, tool in ipairs(screenshot_tools) do
    if tools[tool] then
      has_screenshot_tool = true
      break
    end
  end

  table.insert(health, {
    ok = has_screenshot_tool,
    msg = has_screenshot_tool and "Screenshot tool available"
      or "No screenshot tool found. Install one of: scrot, maim, gnome-screenshot, imagemagick",
  })

  -- Window manager tools
  local has_wm_tool = tools.xdotool or tools.wmctrl
  table.insert(health, {
    ok = has_wm_tool,
    msg = has_wm_tool and "Window manager tool available"
      or "No window manager tool found. Install xdotool or wmctrl for better window targeting",
  })

  -- Clipboard tools
  local has_clipboard_tool = tools.xclip or tools.xsel
  table.insert(health, {
    ok = has_clipboard_tool,
    msg = has_clipboard_tool and "Clipboard tool available" or "No clipboard tool found. Install xclip or xsel",
  })

  return health
end

return M
