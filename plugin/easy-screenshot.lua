-- Plugin commands and default keybindings
if vim.g.loaded_easy_screenshot then
  return
end
vim.g.loaded_easy_screenshot = 1

-- Create user commands
vim.api.nvim_create_user_command("EasyScreenshot", function(opts)
  local args = vim.split(opts.args or "", "%s+", { trimempty = true })
  local process_name = args[1]

  local capture_opts = {}
  if process_name and process_name ~= "" then
    capture_opts.process = process_name
  end

  require("easy-screenshot").capture(capture_opts)
end, {
  nargs = "?",
  desc = "Capture screenshot and paste into markdown (optional: process name)",
})

vim.api.nvim_create_user_command("EasyScreenshotWindow", function(opts)
  if opts.args and opts.args ~= "" then
    -- If args provided, use them directly
    require("easy-screenshot").capture { process = opts.args }
  else
    -- Otherwise, show window picker UI
    require("easy-screenshot").select_and_capture()
  end
end, {
  nargs = "?",
  desc = "Capture screenshot of specific process window",
})

vim.api.nvim_create_user_command("EasyScreenshotListWindows", function(opts)
  local format = opts.args and opts.args ~= "" and opts.args or "short"
  require("easy-screenshot").list_windows { format = format }
end, {
  nargs = "?",
  complete = function()
    return { "short", "detailed" }
  end,
  desc = "List all GUI windows available for screenshot (short|detailed)",
})
