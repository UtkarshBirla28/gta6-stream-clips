# Queue 2 of the GTA 6 clip job (2026-11-21): what queue 1 did not reach before it was stopped for low memory.
# Every step goes through retry.ps1, so it runs ONLY while the laptop is free (owner's rule: the other session
# is the priority): CPU under 70 %, NVIDIA under 60 %, 3 GB RAM free and the other session's render token not
# held. A failed step is reported and the queue goes on.
$T = Join-Path $PSScriptRoot 'retry.ps1'
$G = Split-Path $PSScriptRoot -Parent       # the project folder (kai\, xqc\, speed\ ...)
$SPEED = 'https://www.youtube.com/watch?v=qSyo5d-dVzA'
$results = @()
function Step([string]$name, [string]$log, [string[]]$a) {
    "===== $name  ($(Get-Date -Format HH:mm:ss))"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $T $log @a
    $code = $LASTEXITCODE
    $out | Select-Object -Last 14
    $script:results += "{0,-22} exit {1}" -f $name, $code
}
New-Item -ItemType Directory -Force "$G\xqc\out", "$G\speed\clips_work" | Out-Null

# xQc: face-cam box tightened to the panel's shape (360 x 224), so no strip of gameplay shows beside his face
$xq = @('--max-clips', '1', '--min-score', '0', '--render', '--no-draft', '--hud', 'off', '--device', 'cuda', '--language', 'en',
        '--cam-crop', '4,30,360,224', '--profanity-filter', '--caption-style', 'beast-bold', '--overwrite')
Step 'xqc_carjack' "$G\xqc\out\carjack.log" (@('clip-stream', '--input', "$G\xqc\src\xqc_2.mp4", '--out', "$G\xqc\out\carjack", '--prefix', 'xQc_carjack', '--hook-text', 'XQC STEALS HIS\n{red:FIRST CAR} IN GTA 6') + $xq)
Step 'xqc_chase'   "$G\xqc\out\chase.log"   (@('clip-stream', '--input', "$G\xqc\src\xqc_6.mp4", '--out', "$G\xqc\out\chase",   '--prefix', 'xQc_chase',   '--hook-text', 'FIRST {red:POLICE CHASE}\nIN GTA 6') + $xq)

# IShowSpeed: small audio of the whole stream, keep the first 2 h 10 min, let the tool find the moments
$full = "$G\speed\clips_work\full_139.m4a"
$seed = "$G\speed\clips_work\audio_54f33985.m4a"      # the name the tool expects for this link (sha1 of the URL)
if (-not (Test-Path $seed)) {
    if (-not (Test-Path $full)) {
        Step 'speed_audio' "$G\speed\dl_audio.log" @('ytdlp', '-f', '139', '--no-playlist', '--no-progress', '-o', $full, $SPEED)
    }
    if (Test-Path $full) {
        Step 'speed_cut' "$G\speed\cut_audio.log" @('ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', $full, '-t', '7800', '-c', 'copy', $seed)
    }
}
if (Test-Path $seed) {
    Step 'speed_discover' "$G\speed\discover.log" @('discover-clips', '--url', $SPEED, '--out', "$G\speed\clips.json", '--hud', 'off', '--device', 'cuda', '--language', 'en', '--max-clips', '0')
}
"===== QUEUE 2 DONE  ($(Get-Date -Format HH:mm:ss))"
$results
