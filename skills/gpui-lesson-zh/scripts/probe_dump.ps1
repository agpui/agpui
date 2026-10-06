# Windows probe: capture a minidump of a live process via dbghelp.
# Dump type = Normal + WithHandleData + WithThreadInfo + WithProcessThreadData.
# Note: dumping a session-0 (Services) process requires an elevated console; err=5 means permissions.
# Usage: powershell -ExecutionPolicy Bypass -File probe_dump.ps1 <pid> [outfile.dmp]   (default: probe_dump_<pid>.dmp in cwd)
param([int]$TargetPid, [string]$Out)

if (-not $TargetPid) { Write-Host "usage: probe_dump.ps1 <pid> [outfile.dmp]"; exit 2 }
if (-not $Out) { $Out = "probe_dump_$TargetPid.dmp" }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class DumpProbe {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr CreateFileW([MarshalAs(UnmanagedType.LPWStr)] string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("dbghelp.dll", SetLastError=true)] public static extern bool MiniDumpWriteDump(IntPtr hProc, int pid, IntPtr hFile, uint type, IntPtr exc, IntPtr user, IntPtr cb);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@

$PROCESS_ALL_ACCESS = 0x1F0FFF
$h = [DumpProbe]::OpenProcess($PROCESS_ALL_ACCESS, $false, $TargetPid)
if ($h -eq [IntPtr]::Zero) {
  Write-Host "RED: OpenProcess($TargetPid) failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 1
}
$f = [DumpProbe]::CreateFileW($Out, 0x40000000, 0, [IntPtr]::Zero, 2, 0, [IntPtr]::Zero)  # GENERIC_WRITE, CREATE_ALWAYS
if ($f -eq [IntPtr]::Zero -or $f -eq [IntPtr](-1)) {
  Write-Host "RED: CreateFileW failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 1
}
# MiniDumpWithHandleData | MiniDumpWithThreadInfo | MiniDumpWithProcessThreadData
$dumpType = 0x4 -bor 0x40 -bor 0x100
$ok = [DumpProbe]::MiniDumpWriteDump($h, $TargetPid, $f, $dumpType, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
[DumpProbe]::CloseHandle($f) | Out-Null
[DumpProbe]::CloseHandle($h) | Out-Null

if ($ok) { Write-Host "dump ok: $Out" }
else { Write-Host "dump FAILED err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 1 }
