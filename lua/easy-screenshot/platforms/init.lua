local M = {}

--- Detect the current operating system
---@return string "linux"|"macos"|"windows"|"wsl"
function M.detect_os()
  -- Check for WSL first
  local is_wsl = vim.fn.has "wsl" == 1
  if is_wsl then
    return "wsl"
  end

  -- Check standard Neovim OS detection
  if vim.fn.has "win32" == 1 or vim.fn.has "win64" == 1 then
    return "windows"
  elseif vim.fn.has "mac" == 1 or vim.fn.has "macunix" == 1 then
    return "macos"
  elseif vim.fn.has "unix" == 1 then
    return "linux"
  end

  return "unknown"
end

--- Get the appropriate backend for the current platform
---@return table|nil backend Backend module with capture() function
function M.get_backend()
  local os_type = M.detect_os()

  if os_type == "linux" then
    return require "easy-screenshot.platforms.linux"
  elseif os_type == "macos" then
    return require "easy-screenshot.platforms.macos"
  elseif os_type == "windows" or os_type == "wsl" then
    return require "easy-screenshot.platforms.windows"
  end

  return nil
end

--- Get platform-specific temp directory
---@return string
function M.get_temp_dir()
  local os_type = M.detect_os()

  if os_type == "wsl" then
    -- Use Windows temp accessible from WSL
    return "/mnt/c/tmp/easy-screenshot"
  elseif os_type == "windows" then
    -- Windows temp directory
    local temp = os.getenv "TEMP" or os.getenv "TMP" or "C:/tmp"
    return temp .. "/easy-screenshot"
  else
    -- Unix-like systems
    local temp = os.getenv "TMPDIR" or "/tmp"
    return temp .. "/easy-screenshot"
  end
end

--- Copy file to system clipboard (platform-specific)
---@param filepath string Path to image file
---@param callback function Callback(success, error_msg)
function M.copy_to_clipboard(filepath, callback)
  local os_type = M.detect_os()

  if os_type == "linux" then
    require("easy-screenshot.platforms.linux").copy_to_clipboard(filepath, callback)
  elseif os_type == "macos" then
    require("easy-screenshot.platforms.macos").copy_to_clipboard(filepath, callback)
  elseif os_type == "windows" or os_type == "wsl" then
    require("easy-screenshot.platforms.windows").copy_to_clipboard(filepath, callback)
  else
    callback(false, "Unsupported platform: " .. os_type)
  end
end

return M
