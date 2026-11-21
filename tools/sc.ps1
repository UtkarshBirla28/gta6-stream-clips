# Runs one StreamClipper step for the GTA 6 clip job WITHOUT getting in the way of the other session.
# Owner's rule (2026-11-21): the other session is the priority; use the CPU / graphics card only when free.
#   - Windows priority class Idle: the step only gets CPU time that no other program wants
#   - memory guard: free RAM under SC_MIN_FREE_MB (default 1500) -> the step is stopped (exit 75)
#   - busy guard: if OTHER programs keep the CPU at 92 % or more for about 3 minutes, the step is stopped
#     (exit 75) so it holds no memory while the laptop is busy
#   Finished chunks and finished clips are cached, so a later rerun resumes. retry.ps1 does the waiting.
#   - speech model on the graphics card in int8 mode (see run_sc.py); private yt-dlp settings
# Usage:  powershell -File sc.ps1 <log file> <streamclipper arguments...>
# (No param() block on purpose: with one, PowerShell tries to read "--out" as its own -Out* parameter.)
$Log = $args[0]
$ScArgs = @($args | Select-Object -Skip 1)
if (-not $Log -or $ScArgs.Count -eq 0) { "usage: sc.ps1 <log file> <streamclipper arguments...>"; exit 2 }
$me = [System.Diagnostics.Process]::GetCurrentProcess()
$minFree = if ($env:SC_MIN_FREE_MB) { [int]$env:SC_MIN_FREE_MB } else { 1500 }
$ncpu = [Environment]::ProcessorCount
# StreamClipper checkout with its own .venv (default: <home>\streamclipper); override with STREAMCLIPPER_DIR
$SC = if ($env:STREAMCLIPPER_DIR) { $env:STREAMCLIPPER_DIR } else { Join-Path $env:USERPROFILE 'streamclipper' }
$Py = Join-Path $SC '.venv\Scripts\python.exe'
$Runner = Join-Path $PSScriptRoot 'run_sc.py'
if (-not (Test-Path $Py)) { "StreamClipper not found at $SC (set STREAMCLIPPER_DIR)"; exit 2 }
$env:PYTHONUTF8 = '1'
$env:PYTHONUNBUFFERED = '1'
$env:XDG_CONFIG_HOME = Join-Path $PSScriptRoot 'xdg'
$env:OMP_NUM_THREADS = '2'
$env:OPENBLAS_NUM_THREADS = '2'
$env:MKL_NUM_THREADS = '2'
Set-Location $SC
function Get-FreeMB { [int]((Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory).FreePhysicalMemory / 1KB) }
function Get-MyCpuSec {
    $sum = 0.0
    foreach ($p in (Get-Process python, ffmpeg, ffprobe, node -ErrorAction SilentlyContinue)) {
        try { if ($p.PriorityClass -eq 'Idle') { $sum += $p.CPU } } catch {}
    }
    $sum
}

$free0 = Get-FreeMB
if ($free0 -lt ($minFree + 800)) { "NOT STARTED: only $free0 MB of RAM free (need about $($minFree + 800))"; exit 75 }
$t0 = Get-Date
"[sc.ps1] priority Idle, free RAM $free0 MB, started $(Get-Date -Format HH:mm:ss)" | Out-File -FilePath $Log -Encoding utf8
$argList = @($Runner) + $ScArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$me.PriorityClass = 'Idle'         # the child is created with this class and passes it on to ffmpeg / yt-dlp
$p = Start-Process -FilePath $Py -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardOutput "$Log.out" -RedirectStandardError "$Log.err"
$me.PriorityClass = 'Normal'       # the guard loop itself must stay responsive
$why = ''
$busy = 0
while (-not $p.HasExited) {
    Start-Sleep -Seconds 8
    $free = Get-FreeMB
    if ($free -lt $minFree) { $why = "free RAM $free MB is under $minFree MB"; break }
    $c0 = Get-MyCpuSec; $s0 = Get-Date
    $tot = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    $dt = [math]::Max(0.5, ((Get-Date) - $s0).TotalSeconds)
    $mine = [math]::Max(0, 100 * ((Get-MyCpuSec) - $c0) / ($dt * $ncpu))
    $other = $tot - $mine
    if ($other -ge 92) { $busy++ } else { $busy = 0 }
    if ($busy -ge 16) { $why = "other programs kept the CPU at $([int]$other) % for about 3 minutes"; break }
}
if ($why) {
    "[sc.ps1] $why : stopping this step at $(Get-Date -Format HH:mm:ss)" | Add-Content $Log
    & taskkill /PID $p.Id /T /F | Out-Null
} else { $p.WaitForExit() }
foreach ($part in "$Log.out", "$Log.err") { if (Test-Path $part) { Get-Content $part | Add-Content $Log; Remove-Item $part -Force } }
$code = if ($why) { 75 } else { $p.ExitCode }
"EXIT: $code after $([math]::Round(((Get-Date) - $t0).TotalMinutes, 1)) min" + $(if ($why) { " (stepped aside: $why)" } else { '' })
Get-Content $Log -Tail 45
exit $code
