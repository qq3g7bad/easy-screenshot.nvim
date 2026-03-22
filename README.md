# easy-screenshot.nvim

A Neovim plugin for capturing screenshots and pasting them directly into markdown files with one keybind.

## ✨ Features

- 🖼️ **One-step workflow**: Capture active window screenshot and paste into markdown in one action
- 🎯 **Smart capture**: Automatically captures the currently active window
- 🔍 **Process filtering**: Target specific application windows by process name
- 🔭 **Window picker**: Fuzzy-find windows with [Telescope](https://github.com/nvim-telescope/telescope.nvim) or `vim.ui.select`
- 📁 **Configurable storage**: Control where images are saved, or inherit from [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)
- 🌍 **Multi-platform**: Supports Linux, macOS, Windows, and WSL
- ⚡ **Async operations**: Non-blocking screenshot capture

## 🎯 Why?

Existing solutions require a two-step workflow:

1. Take screenshot with system tool (or manually)
2. Paste from clipboard using img-clip.nvim

**easy-screenshot.nvim** combines both steps into one action, significantly improving documentation workflows.

## 📦 Installation

### Prerequisites

**Linux:**

- One of: `scrot`, `maim`, `gnome-screenshot`, or `imagemagick`
- One of: `xclip` or `xsel` (for clipboard)
- Optional: `xdotool` or `wmctrl` (for window targeting)

**macOS:**

- Built-in tools: `screencapture`, `osascript` (no installation needed)

**Windows/WSL:**

- PowerShell (usually pre-installed)

### Using lazy.nvim

```lua
{
  "qq3g7bad/easy-screenshot.nvim",
  ft = "markdown",
  dependencies = {
    "HakonHarnes/img-clip.nvim", -- Required dependency
  },
  opts = {
    -- Optional configuration (all values below are defaults)
    capture_delay = 0.4,
    fallback_to_selection = true,
    process_name = nil,
    temp_dir = nil,
    picker = "auto",  -- "auto" | "telescope" | "select"
  },
  keys = {
    { "<leader>pS", "<cmd>EasyScreenshot<cr>", desc = "Screenshot: Capture and paste" },
    { "<leader>ps", "<cmd>EasyScreenshotWindow<cr>", desc = "Screenshot: Pick window and capture" },
  },
}
```

## 🚀 Usage

### Basic Usage

1. Open a markdown file
2. Press `<leader>pS` to capture the active window
3. Screenshot is captured and pasted automatically!

### Pick a Window to Capture

Press `<leader>ps` to open a window picker. All visible GUI windows are listed with their process name and title. Select one and it will be captured immediately.

The picker backend is configurable (see [Window Picker](#-window-picker) below).

### Direct Command

Capture a specific process window by name, without opening the picker:

```vim
:EasyScreenshot firefox
:EasyScreenshot google-chrome
:EasyScreenshot code

" Or use the Process variant:
:EasyScreenshotWindow firefox
```

### List Available Windows

To see what process names are available:

```vim
:EasyScreenshotListWindows
" Or with detailed info:
:EasyScreenshotListWindows detailed
```

**Note**: On Linux, window listing and process filtering require `wmctrl` or `xdotool`:

```bash
sudo apt install wmctrl xdotool  # Recommended
```

### Commands

| Command | Description |
|---|---|
| `:EasyScreenshot [process]` | Capture and paste (optional process filter) |
| `:EasyScreenshotWindow [process]` | Open window picker, or capture given process directly |
| `:EasyScreenshotListWindows [short\|detailed]` | List all GUI windows with process names |
| `:checkhealth easy-screenshot` | Check if required tools are installed |

### Lua API

```lua
local screenshot = require("easy-screenshot")

-- Capture active window
screenshot.capture()

-- Capture specific process
screenshot.capture({ process = "firefox" })

-- Open window picker
screenshot.select_and_capture()
```

## 🔭 Window Picker

When `:EasyScreenshotWindow` is called without arguments (or via keybind), it opens an interactive window picker. The plugin supports multiple picker backends:

| Value | Behavior |
|---|---|
| `"auto"` (default) | Uses Telescope if available, otherwise falls back to `vim.ui.select` |
| `"telescope"` | Always use [Telescope](https://github.com/nvim-telescope/telescope.nvim) (fuzzy search) |
| `"select"` | Always use `vim.ui.select` (works without extra plugins) |

```lua
opts = {
  picker = "auto", -- or "telescope" or "select"
}
```

With Telescope, you can fuzzy-search windows by process name or title. The picker displays entries in the format `[process_name] window_title`.

## 🔧 Configuration Options

```lua
{
  -- Capture
  capture_delay = 0.4,              -- Delay before capture (seconds)
  fallback_to_selection = true,     -- Suggest selection tool on failure
  process_name = nil,               -- Default process to target (nil = active window)
  temp_dir = nil,                   -- Temp directory (nil = auto-detect)

  -- Window picker
  picker = "auto",                  -- "auto" | "telescope" | "select"

  -- Image storage (override img-clip defaults)
  dir_path = nil,                   -- Save directory (string or function, nil = img-clip default)
  file_name = nil,                  -- Filename template (nil = img-clip default)
  extension = nil,                  -- Image extension (nil = img-clip default)
  relative_to_current_file = nil,   -- Relative path (nil = img-clip default)
}
```

When `dir_path`, `file_name`, `extension`, or `relative_to_current_file` are set, they override img-clip.nvim's defaults for screenshots taken by this plugin. When `nil`, img-clip.nvim's own configuration is used.

Example with custom storage:

```lua
opts = {
  dir_path = function()
    return "img/" .. os.date("%Y%m%d")
  end,
  file_name = "screenshot_%Y%m%d_%H%M%S",
  extension = "png",
  relative_to_current_file = true,
}
```

## 🏥 Health Check

Run `:checkhealth easy-screenshot` to verify:

- Platform detection
- Required tools availability
- img-clip.nvim installation
- Temp directory accessibility

## 🐛 Troubleshooting

### Linux: "No screenshot tool available"

Install one of the required tools:

```bash
# Ubuntu/Debian
sudo apt install scrot xclip

# Arch Linux
sudo pacman -S maim xclip

# Fedora
sudo dnf install scrot xclip
```

### Linux: "No window found for process"

Make sure `wmctrl` or `xdotool` is installed:

```bash
sudo apt install wmctrl xdotool  # Ubuntu/Debian
```

### WSL: "PowerShell not found"

Ensure you can run `powershell.exe` from WSL:

```bash
powershell.exe -Command "echo test"
```

### macOS: Screenshot not capturing active window

The plugin uses `screencapture -w` which requires window focus. Ensure the target window is active.

## 📝 License

MIT

## 🙏 Credits

- Built on top of [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)
- PowerShell screenshot technique from [misohena.jp](https://misohena.jp/blog/2021-08-08-take-screenshot-on-windows-power-shell.html)
