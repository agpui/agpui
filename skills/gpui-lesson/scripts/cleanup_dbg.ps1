# Remove all [DBG-set] diagnostic lines from the given files (Phase 6 cleanup).
# After cleanup, verify with a grep count back to zero.
# Usage: powershell -ExecutionPolicy Bypass -File cleanup_dbg.ps1 <file> [<file>...]
param([Parameter(Mandatory=$true)][string[]]$Path)

$total = 0
foreach ($p in $Path) {
  $lines = [System.IO.File]::ReadAllLines($p)
  # plain substring match (case-sensitive); -like would treat [] as wildcards
  $kept = @($lines | Where-Object { -not $_.Contains('[DBG-set]') })
  [System.IO.File]::WriteAllLines($p, $kept)
  $removed = $lines.Count - $kept.Count
  Write-Host "$p removed: $removed"
  $total += $removed
}
Write-Host "total removed: $total"
