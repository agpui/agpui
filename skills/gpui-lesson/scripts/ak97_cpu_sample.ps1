# [cpu-loop] idle-CPU feedback loop: normalized% = CookedValue / logical_processors
param([int]$Samples = 5, [int]$Interval = 2)
$n = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Write-Host "LogicalProcessors=$n"
foreach ($name in @('AK97','AK97-Service','lff')) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if (-not $procs) { Write-Host "${name}: not running"; continue }
    try { $path = ($procs | Select-Object -First 1).Path } catch { $path = '?' }
    $max = 0.0
    (Get-Counter "\Process($name*)\% Processor Time" -SampleInterval $Interval -MaxSamples $Samples -ErrorAction SilentlyContinue).CounterSamples | ForEach-Object {
        $norm = $_.CookedValue / $n
        if ($norm -gt $max) { $max = $norm }
    }
    Write-Host ("{0} (path={1}): PEAK_NORMALIZED={2:N1}%" -f $name, $path, $max)
}
