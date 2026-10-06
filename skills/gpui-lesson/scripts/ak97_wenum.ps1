# [cpu-loop] enumerate visible top-level windows of a PID (GPUI self-drawn, no UIA)
param([int]$Pid0)
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WEnum3 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
}
'@
$found = 0
$cb = [WEnum3+EnumProc]{ param($h, $l)
  $p = 0
  [WEnum3]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ($p -eq $Pid0 -and [WEnum3]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 256
    [WEnum3]::GetWindowText($h, $sb, 256) | Out-Null
    Write-Host ("visible: hwnd=$h title=[" + $sb.ToString() + "]")
    $script:found++
  }
  $true
}
[WEnum3]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
Write-Host "visible_window_count=$found"
