local M = {}

--- Run health checks
function M.check()
  local platform = require "easy-screenshot.platforms"
  local os_type = platform.detect_os()

  vim.health.start "easy-screenshot.nvim"

  -- Platform detection
  vim.health.info("Detected platform: " .. os_type)

  -- Check img-clip.nvim dependency
  local has_imgclip, imgclip = pcall(require, "img-clip")
  if has_imgclip then
    vim.health.ok "img-clip.nvim is installed"
  else
    vim.health.error("img-clip.nvim not found", {
      "Install img-clip.nvim: https://github.com/HakonHarnes/img-clip.nvim",
      "Add to your lazy.nvim config as a dependency",
    })
  end

  -- Platform-specific checks
  local backend = platform.get_backend()
  if backend and backend.check_health then
    local health_results = backend.check_health()

    for _, result in ipairs(health_results) do
      if result.ok then
        vim.health.ok(result.msg)
      else
        vim.health.warn(result.msg, result.advice or {})
      end
    end
  else
    vim.health.error("No backend available for platform: " .. os_type)
  end

  -- Check temp directory
  local config = require "easy-screenshot.config"
  local defaults = config.get_defaults()
  local temp_dir = platform.get_temp_dir()

  local temp_exists = vim.fn.isdirectory(temp_dir) == 1
  if temp_exists then
    vim.health.ok("Temp directory exists: " .. temp_dir)
  else
    local create_success = pcall(vim.fn.mkdir, temp_dir, "p")
    if create_success then
      vim.health.ok("Created temp directory: " .. temp_dir)
    else
      vim.health.warn("Temp directory doesn't exist and couldn't be created: " .. temp_dir)
    end
  end
end

return M
