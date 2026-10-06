# Windows probe: detect hung windows + enumerate window states.
# Red signal   = IsHungAppWindow() true (message pump blocked >= 5s) or no process found.
# Green signal = all windows not hung.
# Usage: powershell -ExecutionPolicy Bypass -File probe_hung.ps1 [<process-name>]   (default: AK97)
param([string]$Name = "AK97")

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class HungProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

# exact process-name match, same criterion as the original tasklist /FI probe
$procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
if (-not $procs) { Write-Host "RED: no $Name process"; exit 2 }
$pids = @($procs.Id)
Write-Host "$Name pids: $($pids -join ',')"

$script:anyHung = $false
$cb = [HungProbe+EnumProc]{ param($h, $l)
  $p = 0
  [HungProbe]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  if ($pids -contains [int]$p) {
    $title = New-Object System.Text.StringBuilder 128
    $cls = New-Object System.Text.StringBuilder 128
    [HungProbe]::GetWindowText($h, $title, 128) | Out-Null
    [HungProbe]::GetClassName($h, $cls, 128) | Out-Null
    $r = New-Object HungProbe+RECT
    [HungProbe]::GetWindowRect($h, [ref]$r) | Out-Null
    $hung = [HungProbe]::IsHungAppWindow($h)
    $vis = [HungProbe]::IsWindowVisible($h)
    Write-Host ("hwnd={0:x} pid={1} vis={2} hung={3} w={4} h={5} title=[{6}] class=[{7}]" -f `
      $h.ToInt64(), $p, $vis, $hung, ($r.Right - $r.Left), ($r.Bottom - $r.Top), $title.ToString(), $cls.ToString())
    if ($hung) { $script:anyHung = $true }
  }
  return $true
}
[HungProbe]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null

if ($script:anyHung) { Write-Host "VERDICT: RED hung window present"; exit 1 }
else { Write-Host "VERDICT: no hung window"; exit 0 }
