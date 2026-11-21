# Runs one StreamClipper step through sc.ps1, but ONLY while the laptop is free.
# Owner's rule (2026-11-21): the other session is the priority; use the CPU / graphics card only when free.
#   - before every try it waits until the laptop is clearly free:
#       CPU under SC_START_CPU % (default 70) on three checks in a row, 20 s apart,
#       NVIDIA card under 60 % busy, and at least SC_RESUME_FREE_MB (default 3000) MB of RAM free
#   - when sc.ps1 steps aside (exit code 75: memory low, or the CPU got busy again) it goes back to waiting
#     and resumes from the cache
#   - any other failure is returned as it is, so real errors are not hidden
# Usage:  powershell -File retry.ps1 <log file> <streamclipper arguments...>
$Log = $args[0]
$Rest = @($args | Select-Object -Skip 1)
$resumeAt = if ($env:SC_RESUME_FREE_MB) { [int]$env:SC_RESUME_FREE_MB } else { 3000 }
$startCpu = if ($env:SC_START_CPU) { [int]$env:SC_START_CPU } else { 70 }
$maxWait = if ($env:SC_MAX_WAIT_MIN) { [int]$env:SC_MAX_WAIT_MIN } else { 720 }
function Get-FreeMB { [int]((Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory).FreePhysicalMemory / 1KB) }
function Get-Cpu { [int](Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue }
function Get-Gpu { try { [int]((& nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits) | Select-Object -First 1) } catch { 0 } }
# The other session takes Desktop\RAM_TOKEN.txt for each of its video renders. While it holds the token
# (and the token is younger than 100 minutes) this job does not start a step.
function Test-TokenHeld {
    $f = Join-Path $env:USERPROFILE 'Desktop\RAM_TOKEN.txt'
    if (-not (Test-Path $f)) { return $false }
    try { ((Get-Date) - (Get-Item $f).LastWriteTime).TotalMinutes -lt 100 } catch { $false }
}
$t0 = Get-Date
$try = 0
$waited = 0
while ($true) {
    # ---- wait until the laptop is free
    $ok = 0
    while ($ok -lt 3) {
        if (((Get-Date) - $t0).TotalMinutes -gt $maxWait) { "[retry] gave up: the laptop was not free within $maxWait min"; exit 75 }
        $cpu = Get-Cpu; $gpu = Get-Gpu; $free = Get-FreeMB
        if ($cpu -lt $startCpu -and $gpu -lt 60 -and $free -ge $resumeAt -and -not (Test-TokenHeld)) { $ok++ } else { $ok = 0; $waited++ }
        if ($ok -lt 3) { Start-Sleep -Seconds $(if ($ok -gt 0) { 20 } else { 45 }) }
    }
    $try++
    "[retry] laptop free at $(Get-Date -Format HH:mm:ss) (CPU $cpu %, NVIDIA $gpu %, RAM free $free MB): try $try"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'sc.ps1') $Log @Rest
    $code = $LASTEXITCODE
    if ($code -ne 75) { break }
    "[retry] try $try stepped aside at $(Get-Date -Format HH:mm:ss): $($out | Select-Object -First 1)"
}
"[retry] finished with exit code $code after $try tries, $([math]::Round(((Get-Date) - $t0).TotalMinutes, 1)) min in total ($waited busy checks waited out)"
$out | Select-Object -Last 45
exit $code
