# GTA 6 stream clips

Turns long GTA 6 streams (YouTube, Twitch, Kick) into ready-to-post vertical Shorts: the streamer's face cam on top,
gameplay below, a headline and word-by-word captions, 1080x1920.

The heavy lifting (transcription, layout, captions, rendering, export checks) is done by
[StreamClipper](https://github.com/alokbaraii/streamclipper). This repo is the glue around it: fixes for a Windows
laptop with an older NVIDIA card, a "polite mode" that only uses the PC when it is free, helpers to pick moments by
reading the transcript, and the clip specs behind the first example clips.

## What is in here

| File | What it does |
|---|---|
| `tools/run_sc.py` | Runs StreamClipper with fixes: the speech model runs in int8 on GTX 16xx cards (float16 gives broken output there, float32 needs about 4.6 GB), a small GPU batch, video encoding moved to Intel Quick Sync with NVIDIA decoding (falls back to the CPU if that fails). Also passes `ytdlp` and `ffmpeg` through, so downloads run under the same guards. |
| `tools/sc.ps1` | Runs one step politely: Windows Idle priority; stops the step if free RAM drops under 1.5 GB or other programs hold the CPU at 92 % or more for about 3 minutes. Finished work is cached, so a rerun resumes. |
| `tools/retry.ps1` | Waits until the PC is free (CPU under 70 %, NVIDIA under 60 %, 3 GB RAM free, no render token held by another job), runs the step, and goes back to waiting when it steps aside. |
| `tools/words.py` | Prints the transcript of a time range with timestamps, to pick moments by reading. |
| `tools/show_clips.py` | Prints StreamClipper's ranked moments with what is said in each. |
| `tools/make_spec.py` | Turns a hand-picked time range of a transcribed stream into a clip spec, with word times shifted to the slice's own clock. Prints the slice range to download. |
| `tools/fix_words.py` | Gives zero-length Whisper words a real duration (otherwise they fail the caption check). |
| `tools/queue1.ps1`, `tools/queue2.ps1` | The batches used for the first examples. |
| `tools/xdg/yt-dlp/config` | Private yt-dlp settings (Node as the JavaScript runtime for YouTube); the normal yt-dlp config is not touched. |
| `kai/specs/`, `speed/specs/` | Clip specs of the example clips: hand-set face-cam boxes, headlines and captions. |

## Setup (Windows)

1. Install StreamClipper into `%USERPROFILE%\streamclipper` (or set `STREAMCLIPPER_DIR`):
   ```powershell
   git clone https://github.com/alokbaraii/streamclipper.git $env:USERPROFILE\streamclipper
   cd $env:USERPROFILE\streamclipper
   py -3.12 -m venv .venv
   .venv\Scripts\python -m pip install -e ".[asr,gpu,vision]"
   .venv\Scripts\streamclipper doctor
   ```
2. ffmpeg on the PATH (`winget install Gyan.FFmpeg`) and Node.js (yt-dlp uses it for YouTube).
3. Clone this repo anywhere; the scripts find their own folder.

## Making a clip

```powershell
# 1. Find moments in a stream: audio-only download, transcription on the GPU, ranked list in clips.json
powershell -File tools\retry.ps1 kai\discover.log discover-clips --url <stream link> --out kai\clips.json --hud off --device cuda --language en

# 2. Read the top picks, and the transcript around anything interesting
py tools\show_clips.py kai\clips.json 15
py tools\words.py kai\clips_work\asr 5300 5340

# 3. Write a spec for the moment (prints SLICE <start> <end>), download that slice, render
py tools\make_spec.py kai\clips_work\asr Kai_bad_guy 5310 5337.8 beast-bold "SO {red:I'M} THE\nBAD GUY?!" kai\specs
powershell -File tools\retry.ps1 kai\out\dl.log download-vod --url <stream link> --start <start> --end <end> --out kai\src\Kai_bad_guy.mp4
powershell -File tools\retry.ps1 kai\out\render.log render --spec kai\specs\Kai_bad_guy.json --out kai\out --profanity-filter
```

Then add `"cam_crop": [x, y, w, h]` (and `"game_crop"`) to the spec, measured on one frame of the slice. For a
short Twitch clip that is already the right moment, `clip-stream --input <file> --render --no-draft --cam-crop ...`
does everything in one step (see `tools/queue2.ps1`).

## Things learned on real streams

- **Pick moments by reading.** StreamClipper's own ranking is mostly loudness. On long GTA streams many top picks
  were noise; the best moments came from reading the transcript.
- **Set the face cam by hand.** Its automatic face-cam detection picked a patch of road on one stream. Measure the
  box on one frame and pass it as `cam_crop`.
- **Edited VODs that zoom on the face:** use `reframe_segments` to go full screen for those seconds
  (see `kai/specs/Kai_bodies.json`).
- **NVIDIA encoding** in ffmpeg 9 needs NVIDIA driver 610 or newer; with an older driver, Quick Sync still works.
- **24-hour YouTube streams:** `--download-sections` stalled. Downloading the small audio format (139, about 500 MB
  for 24 h) and cutting it locally was fast; video slices were cut with ffmpeg from the direct `yt-dlp -g` URL.
- **Caption check fails on one word?** Usually a zero-length Whisper word: `py tools\fix_words.py <clip.json>`, then
  `render --spec <clip.json> --caption-style beast-bold`.

## Rules

Only clip streams you have permission to clip (the streamer's clipping program or their OK), follow the rules of the
platform you post on, and credit the streamer. This repo stores no videos, audio or transcripts.

## License

AGPL-3.0, the same as StreamClipper, which this code imports.
