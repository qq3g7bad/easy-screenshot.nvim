---@class EasyScreenshotConfig
---@field fallback_to_selection boolean
---@field process_name string|nil
---@field capture_delay number
---@field temp_dir string|nil
---@field dir_path string|function|nil Directory to save images (string, function, or nil to use img-clip default)
---@field file_name string|nil Filename template (e.g. "%Y%m%d_%H%M%S"), nil to use img-clip default
---@field extension string|nil Image extension (e.g. "png"), nil to use img-clip default
---@field relative_to_current_file boolean|nil Whether dir_path is relative to current file, nil to use img-clip default
---@field picker "auto"|"telescope"|"select" Window picker backend ("auto" tries telescope, then vim.ui.select)

local M = {}

--- Default configuration
---@type EasyScreenshotConfig
local defaults = {
  fallback_to_selection = true,
  process_name = nil,
  capture_delay = 0.4,
  temp_dir = nil, -- Will auto-detect if nil
  dir_path = nil, -- nil = use img-clip default
  file_name = nil, -- nil = use img-clip default
  extension = nil, -- nil = use img-clip default
  relative_to_current_file = nil, -- nil = use img-clip default
  picker = "auto", -- "auto" | "telescope" | "select"
}

--- Setup and merge user configuration with defaults
---@param opts EasyScreenshotConfig User provided options
---@return EasyScreenshotConfig
function M.setup(opts)
  local config = vim.tbl_deep_extend("force", defaults, opts)

  -- Validate config
  if type(config.capture_delay) ~= "number" or config.capture_delay < 0 then
    vim.notify("easy-screenshot: capture_delay must be a non-negative number", vim.log.levels.WARN)
    config.capture_delay = defaults.capture_delay
  end

  if config.process_name and type(config.process_name) ~= "string" then
    vim.notify("easy-screenshot: process_name must be a string or nil", vim.log.levels.WARN)
    config.process_name = nil
  end

  -- Auto-detect temp_dir if not provided
  if not config.temp_dir then
    local platform = require "easy-screenshot.platforms"
    config.temp_dir = platform.get_temp_dir()
  end

  return config
end

--- Get default configuration
---@return EasyScreenshotConfig
function M.get_defaults()
  return vim.deepcopy(defaults)
end

return M
