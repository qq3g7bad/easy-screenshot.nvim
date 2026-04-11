local M = {}
local utils = require "easy-screenshot.utils"

--- Convert a Unix path to a Windows path (for WSL)
---@param path string
---@return string
local function to_win_path(path)
  if vim.fn.has "wsl" == 1 then
    if path:match("^/mnt/(%a)") then
      -- /mnt/<drive>/... -> <DRIVE>:\...
      local win = path:gsub("^/mnt/(%a)", "%1:")
      return win:gsub("/", "\\")
    else
      -- Linux filesystem path -> UNC path so that powershell.exe can
      -- resolve it regardless of the current working directory.
      local distro = os.getenv("WSL_DISTRO_NAME") or "Ubuntu"
      return "\\\\wsl.localhost\\" .. distro .. path:gsub("/", "\\")
    end
  end
  return path
end

--- Write a PowerShell script to a temp file and execute it
---@param ps_code string PowerShell code
---@param temp_dir string Directory for the script file
---@param callback function Callback(exit_code, stdout, stderr)
local function run_ps(ps_code, temp_dir, callback)
  local dir = temp_dir or vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  vim.fn.mkdir(dir, "p")
  local script_file = dir .. "/ps_" .. math.random(1000, 9999) .. ".ps1"
  local f = io.open(script_file, "w")
  if not f then
    callback(1, "", "Failed to write PowerShell script to " .. script_file)
    return
  end
  -- Force UTF-8 output so Japanese (and other non-ASCII) window titles are
  -- not mangled by the default CP932/Shift-JIS console encoding.
  f:write "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n"
  f:write(ps_code)
  f:close()

  utils.execute_async("powershell.exe", {
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    to_win_path(script_file),
  }, function(exit_code, stdout, stderr)
    vim.fn.delete(script_file)
    callback(exit_code, stdout, stderr)
  end)
end

--- Shared C# type definition for Win32 window APIs
local WIN32_TYPES = [[
Add-Type -Type @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace Win32Util {
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public class WinApi {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetProcessDPIAware();

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hWnd, uint dwAttribute, out RECT lpRect, int cbAttribute);

        public const uint DWMWA_EXTENDED_FRAME_BOUNDS = 0x09;

        public static RECT GetDwmWindowRect(IntPtr hWnd) {
            RECT rect = new RECT();
            DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf(typeof(RECT)));
            return rect;
        }

        public static string GetWindowTitle(IntPtr hWnd) {
            int len = GetWindowTextLength(hWnd);
            if (len == 0) return "";
            StringBuilder sb = new StringBuilder(len + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static List<IntPtr> GetVisibleWindows() {
            List<IntPtr> windows = new List<IntPtr>();
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (IsWindowVisible(hWnd) && GetWindowTextLength(hWnd) > 0) {
                    windows.Add(hWnd);
                }
                return true;
            }, IntPtr.Zero);
            return windows;
        }
    }
}
'@
]]

--- List all visible windows with their process names
---@param callback function Callback(success, windows_or_error)
function M.list_windows(callback)
  local ps_code = WIN32_TYPES
    .. [[
$windows = [Win32Util.WinApi]::GetVisibleWindows()
foreach ($hWnd in $windows) {
    $wpid = 0
    [Win32Util.WinApi]::GetWindowThreadProcessId($hWnd, [ref]$wpid) | Out-Null
    $title = [Win32Util.WinApi]::GetWindowTitle($hWnd)
    try {
        $proc = (Get-Process -Id $wpid -ErrorAction SilentlyContinue).ProcessName
    } catch {
        $proc = "unknown"
    }
    if ($proc -and $title) {
        Write-Output "$wpid`t$proc`t$hWnd`t$title"
    }
}
]]

  run_ps(ps_code, vim.fn.fnamemodify(vim.fn.tempname(), ":h"), function(exit_code, stdout, stderr)
    if exit_code ~= 0 then
      callback(false, "PowerShell failed: " .. stderr)
      return
    end

    local windows = {}
    for line in stdout:gmatch "[^\r\n]+" do
      local pid, proc, hwnd, title = line:match "^(%d+)\t([^\t]+)\t([^\t]+)\t(.+)$"
      if pid then
        -- Strip zero-width characters (U+200B, U+200C, U+200D, U+FEFF) that
        -- apps like Edge embed in window titles.
        title = vim.fn.substitute(title, "[\\u200b\\u200c\\u200d\\ufeff]", "", "g")
        table.insert(windows, {
          id = hwnd,
          pid = pid,
          process = proc,
          title = title,
        })
      end
    end
    callback(true, windows)
  end)
end

--- Capture screenshot using PowerShell
---@param opts table Options
---@param callback function Callback(success, filepath_or_error)
function M.capture(opts, callback)
  vim.fn.mkdir(opts.temp_dir, "p")
  local temp_file = utils.get_temp_filepath(opts.temp_dir)
  local capture_path = to_win_path(temp_file)

  -- Escape backslashes for embedding in PowerShell string
  local ps_path = capture_path:gsub("\\", "\\\\")

  local ps_code
  if opts.hwnd then
    -- Capture by exact window handle (from picker)
    ps_code = WIN32_TYPES
      .. string.format(
        [[
Start-Sleep -Milliseconds %d

[Win32Util.WinApi]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing

$targetHWnd = [IntPtr]::new(%s)

$rect = New-Object Win32Util.RECT
[Win32Util.WinApi]::GetWindowRect($targetHWnd, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top

if ($w -le 0 -or $h -le 0) {
    Write-Error "Invalid window dimensions: ${w}x${h}"
    exit 1
}

$bmp = New-Object System.Drawing.Bitmap $w, $h
$graphics = [Drawing.Graphics]::FromImage($bmp)
$hdc = $graphics.GetHdc()
# PW_RENDERFULLCONTENT = 2 captures DWM-composed content
[Win32Util.WinApi]::PrintWindow($targetHWnd, $hdc, 2) | Out-Null
$graphics.ReleaseHdc($hdc)
$bmp.Save("%s")
$graphics.Dispose()
$bmp.Dispose()
]],
        math.floor(opts.capture_delay * 1000),
        opts.hwnd,
        ps_path
      )
  elseif opts.process then
    -- Capture by process name (fallback)
    ps_code = WIN32_TYPES
      .. string.format(
        [[
Start-Sleep -Milliseconds %d

[Win32Util.WinApi]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Drawing

$targetName = "%s"
$targetHWnd = [IntPtr]::Zero

$windows = [Win32Util.WinApi]::GetVisibleWindows()
foreach ($hWnd in $windows) {
    $wpid = 0
    [Win32Util.WinApi]::GetWindowThreadProcessId($hWnd, [ref]$wpid) | Out-Null
    try {
        $proc = (Get-Process -Id $wpid -ErrorAction SilentlyContinue).ProcessName
    } catch {
        continue
    }
    if ($proc -and $proc -like "*$targetName*") {
        $targetHWnd = $hWnd
        break
    }
}

if ($targetHWnd -eq [IntPtr]::Zero) {
    Write-Error "No window found for process: $targetName"
    exit 1
}

$rect = New-Object Win32Util.RECT
[Win32Util.WinApi]::GetWindowRect($targetHWnd, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top

if ($w -le 0 -or $h -le 0) {
    Write-Error "Invalid window dimensions: ${w}x${h}"
    exit 1
}

$bmp = New-Object System.Drawing.Bitmap $w, $h
$graphics = [Drawing.Graphics]::FromImage($bmp)
$hdc = $graphics.GetHdc()
[Win32Util.WinApi]::PrintWindow($targetHWnd, $hdc, 2) | Out-Null
$graphics.ReleaseHdc($hdc)
$bmp.Save("%s")
$graphics.Dispose()
$bmp.Dispose()
]],
        math.floor(opts.capture_delay * 1000),
        opts.process,
        ps_path
      )
  else
    -- Capture the foreground window (original behavior)
    ps_code = WIN32_TYPES
      .. string.format(
        [[
Start-Sleep -Milliseconds %d

[Win32Util.WinApi]::SetProcessDPIAware() | Out-Null

$hwnd = [Win32Util.WinApi]::GetForegroundWindow()
$rect = [Win32Util.WinApi]::GetDwmWindowRect($hwnd)

Add-Type -AssemblyName System.Windows.Forms,System.Drawing

$bounds   = [Drawing.Rectangle]::FromLTRB($rect.Left, $rect.Top, $rect.Right, $rect.Bottom)
$bmp      = New-Object System.Drawing.Bitmap ([int]$bounds.Width), ([int]$bounds.Height)
$graphics = [Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
$bmp.Save("%s")
$graphics.Dispose()
$bmp.Dispose()
]],
        math.floor(opts.capture_delay * 1000),
        ps_path
      )
  end

  run_ps(ps_code, opts.temp_dir, function(exit_code, stdout, stderr)
    if exit_code == 0 and utils.file_exists(temp_file) then
      callback(true, temp_file)
    else
      callback(false, "PowerShell screenshot failed: " .. stderr)
    end
  end)
end

--- Copy image to clipboard using PowerShell
---@param filepath string Path to image
---@param callback function Callback(success, error_msg)
function M.copy_to_clipboard(filepath, callback)
  local win_path = to_win_path(filepath)
  local ps_code = string.format(
    [[
Add-Type -AssemblyName System.Windows.Forms
$image = [System.Drawing.Image]::FromFile("%s")
[System.Windows.Forms.Clipboard]::SetImage($image)
$image.Dispose()
]],
    win_path
  )

  run_ps(ps_code, vim.fn.fnamemodify(vim.fn.tempname(), ":h"), function(exit_code, stdout, stderr)
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

  local has_powershell = vim.fn.executable "powershell.exe" == 1
  table.insert(health, {
    ok = has_powershell,
    msg = has_powershell and "PowerShell available"
      or "PowerShell not found. Required for Windows/WSL screenshot capture",
  })

  return health
end

return M
