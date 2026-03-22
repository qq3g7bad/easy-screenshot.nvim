---@class EasyScreenshot
---@field config EasyScreenshotConfig
local M = {}

---@class EasyScreenshotConfig
---@field fallback_to_selection boolean If active window capture fails, fall back to selection tool
---@field process_name string|nil Optional: specific process to target
---@field capture_delay number Delay before capture (seconds)
---@field temp_dir string|nil Auto-detect or use system temp

---@type EasyScreenshotConfig
M.config = {}

--- Setup the plugin
---@param opts EasyScreenshotConfig|nil User configuration
function M.setup(opts)
  local config = require "easy-screenshot.config"
  M.config = config.setup(opts or {})
end

--- Capture screenshot and paste into markdown
---@param opts table|nil Options: { process = "process_name" }
function M.capture(opts)
  opts = opts or {}

  if not M.config or not M.config.capture_delay then
    vim.notify("easy-screenshot.nvim not configured. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  local platform = require "easy-screenshot.platforms"
  local backend = platform.get_backend()

  if not backend then
    vim.notify("No screenshot backend available for your platform", vim.log.levels.ERROR)
    return
  end

  -- Merge config with per-call options
  local capture_opts = vim.tbl_deep_extend("force", {
    process = M.config.process_name,
    temp_dir = M.config.temp_dir,
    capture_delay = M.config.capture_delay,
  }, opts)

  -- Build img-clip overrides from config
  local imgclip_opts = {}
  if M.config.dir_path then
    imgclip_opts.dir_path = M.config.dir_path
  end
  if M.config.file_name then
    imgclip_opts.file_name = M.config.file_name
  end
  if M.config.extension then
    imgclip_opts.extension = M.config.extension
  end
  if M.config.relative_to_current_file ~= nil then
    imgclip_opts.relative_to_current_file = M.config.relative_to_current_file
  end

  backend.capture(capture_opts, function(success, result)
    if not success then
      local fallback_msg = M.config.fallback_to_selection and " Try using a selection tool instead." or ""
      vim.notify("Screenshot capture failed: " .. (result or "Unknown error") .. fallback_msg, vim.log.levels.ERROR)
      return
    end

    -- Result is the path to the temp screenshot file
    local utils = require "easy-screenshot.utils"
    utils.paste_with_imgclip(result, imgclip_opts, function(paste_success, paste_result)
      if paste_success then
        vim.notify("Screenshot pasted successfully", vim.log.levels.INFO)
      else
        vim.notify("Failed to paste screenshot: " .. (paste_result or "Unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Check if telescope is available
---@return boolean
local function has_telescope()
  local ok = pcall(require, "telescope")
  return ok
end

--- Pick a window using Telescope
---@param windows table List of window objects
---@param on_select function Callback(window)
local function pick_with_telescope(windows, on_select)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  pickers
    .new({}, {
      prompt_title = "Select window to capture",
      finder = finders.new_table {
        results = windows,
        entry_maker = function(entry)
          local display = string.format("[%s] %s", entry.process, entry.title)
          return {
            value = entry,
            display = display,
            ordinal = entry.process .. " " .. entry.title,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            on_select(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Pick a window using vim.ui.select
---@param windows table List of window objects
---@param on_select function Callback(window)
local function pick_with_select(windows, on_select)
  vim.ui.select(windows, {
    prompt = "Select window to capture:",
    format_item = function(item)
      return string.format("[%s] %s", item.process, item.title)
    end,
  }, function(choice)
    if choice then
      on_select(choice)
    end
  end)
end

--- Show a picker of windows and capture the selected one
function M.select_and_capture()
  if not M.config or not M.config.capture_delay then
    vim.notify("easy-screenshot.nvim not configured. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  local platform = require "easy-screenshot.platforms"
  local backend = platform.get_backend()

  if not backend or not backend.list_windows then
    vim.notify("Window listing not available for your platform", vim.log.levels.WARN)
    return
  end

  backend.list_windows(function(success, result)
    if not success then
      vim.notify("Failed to list windows: " .. result, vim.log.levels.ERROR)
      return
    end

    if #result == 0 then
      vim.notify("No GUI windows found", vim.log.levels.WARN)
      return
    end

    -- Sort by process name
    table.sort(result, function(a, b)
      return a.process < b.process
    end)

    local on_select = function(window)
      M.capture { process = window.process, hwnd = window.id }
    end

    local picker = M.config.picker or "auto"
    if picker == "telescope" or (picker == "auto" and has_telescope()) then
      pick_with_telescope(result, on_select)
    else
      pick_with_select(result, on_select)
    end
  end)
end

--- List all available GUI windows
---@param opts table|nil Options: { format = "short"|"detailed" }
function M.list_windows(opts)
  opts = opts or {}
  local format = opts.format or "short"

  local platform = require "easy-screenshot.platforms"
  local backend = platform.get_backend()

  if not backend or not backend.list_windows then
    vim.notify("Window listing not available for your platform", vim.log.levels.WARN)
    return
  end

  vim.notify("Fetching window list...", vim.log.levels.INFO)

  backend.list_windows(function(success, result)
    if not success then
      vim.notify("Failed to list windows: " .. result, vim.log.levels.ERROR)
      return
    end

    if #result == 0 then
      vim.notify("No GUI windows found", vim.log.levels.WARN)
      return
    end

    -- Display in a new buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_name(buf, "Screenshot Windows")

    local lines = { "Available GUI Windows for Screenshot", "" }
    table.insert(lines, "Usage: :EasyScreenshot <process_name>")
    table.insert(lines, "")

    -- Sort by process name
    table.sort(result, function(a, b)
      return a.process < b.process
    end)

    if format == "detailed" then
      table.insert(lines, string.format("%-20s %-10s %-15s %s", "PROCESS", "PID", "WINDOW_ID", "TITLE"))
      table.insert(lines, string.rep("-", 100))
      for _, win in ipairs(result) do
        local line =
          string.format("%-20s %-10s %-15s %s", win.process, win.pid, win.id, vim.fn.strcharpart(win.title, 0, 50))
        table.insert(lines, line)
      end
    else
      -- Group by process
      local processes = {}
      for _, win in ipairs(result) do
        if not processes[win.process] then
          processes[win.process] = {}
        end
        table.insert(processes[win.process], win.title)
      end

      local proc_names = {}
      for proc, _ in pairs(processes) do
        table.insert(proc_names, proc)
      end
      table.sort(proc_names)

      table.insert(lines, string.format("%-25s %s", "PROCESS NAME", "WINDOWS"))
      table.insert(lines, string.rep("-", 80))
      for _, proc in ipairs(proc_names) do
        local count = #processes[proc]
        local title = processes[proc][1]
        local title_charlen = vim.fn.strchars(title)
        local example = vim.fn.strcharpart(title, 0, 40)
        table.insert(
          lines,
          string.format(
            '%-25s %d window%s - "%s%s"',
            proc,
            count,
            count > 1 and "s" or "",
            example,
            title_charlen > 40 and "..." or ""
          )
        )
      end
    end

    table.insert(lines, "")
    table.insert(lines, "Press 'q' to close this window")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Open in a split
    vim.cmd "botright split"
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_height(0, math.min(#lines + 2, 20))

    -- Set up keymapping to close with 'q'
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
  end)
end

return M
