"""Run StreamClipper with local tweaks for this laptop (GTX 1660 Ti 6 GB, 16 GB RAM, shared with other work).

The CPU here is usually full with another job, while the NVIDIA card is mostly free. So this wrapper moves as
much as it can onto the card, without changing the StreamClipper source:

1. Speech model: GTX 16xx cards are known to give broken output in half precision (float16), and full float32
   takes about 4.6 GB of video memory here. Every GPU model load therefore uses int8 weights with float32 maths
   (int8_float32): safe on this card and under about 2 GB. The tool's own log line may still say "float16".
2. GPU batch size is capped (SC_BATCH, default 4) to keep video memory low.
3. Whisper's CPU side is capped at 2 threads.
4. Video: every ffmpeg call that encodes with libx264 is rewritten to encode on the Intel graphics chip
   (h264_qsv) and to decode video inputs on the NVIDIA card (-hwaccel cuda). If that ffmpeg call fails, the
   original CPU command runs instead, so a graphics problem can never lose a clip. Turn off with SC_NVENC=0.

Usage: .venv\\Scripts\\python.exe run_sc.py <any streamclipper arguments>
"""

import os
import subprocess
import sys

import faster_whisper

# ---------------------------------------------------------------- speech model on the card, small and safe
_Orig = faster_whisper.WhisperModel
_GPU_TYPE = os.environ.get("SC_GPU_TYPE", "int8_float32")
_BATCH = int(os.environ.get("SC_BATCH", "4"))


def _patched(name, device="auto", compute_type="default", **kw):
    if device == "cuda" and compute_type != _GPU_TYPE:
        print(f"[run_sc] GTX 1660 Ti: using {_GPU_TYPE} instead of {compute_type}", flush=True)
        compute_type = _GPU_TYPE
    kw.setdefault("cpu_threads", 2)
    return _Orig(name, device=device, compute_type=compute_type, **kw)


faster_whisper.WhisperModel = _patched

_orig_batched = faster_whisper.BatchedInferencePipeline.transcribe


def _batched(self, audio, *a, **kw):
    if kw.get("batch_size", 0) > _BATCH:
        kw["batch_size"] = _BATCH
    return _orig_batched(self, audio, *a, **kw)


faster_whisper.BatchedInferencePipeline.transcribe = _batched

# ---------------------------------------------------------------- video encode / decode on the card
_NVENC = os.environ.get("SC_NVENC", "1") != "0"
_VIDEO_EXT = (".mp4", ".mkv", ".mov", ".webm", ".m4v", ".ts", ".flv")
_X264_PRESETS = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"}


def _to_gpu(cmd):
    """libx264 ffmpeg command -> the same command with NVENC encode and NVDEC decode, or None if not applicable."""
    if not isinstance(cmd, (list, tuple)) or not cmd:
        return None
    args = [str(c) for c in cmd]
    if os.path.splitext(os.path.basename(args[0]))[0].lower() != "ffmpeg" or "libx264" not in args:
        return None
    out, i = [], 0
    while i < len(args):
        a = args[i]
        nxt = args[i + 1] if i + 1 < len(args) else ""
        if a == "-i" and nxt.lower().endswith(_VIDEO_EXT):
            out += ["-hwaccel", "cuda", "-i", nxt]
            i += 2
        elif a == "libx264":
            # Intel Quick Sync. The NVIDIA encoder cannot be used here: this ffmpeg build needs NVIDIA
            # driver 610 or newer and the laptop has 581.80 (tested 2026-11-21). NVIDIA decoding does work.
            out.append("h264_qsv")
            i += 1
        elif a == "-crf":
            # Quick Sync's quality scale sits about 3 steps above x264's CRF for a similar look
            out += ["-global_quality", str(min(51, int(float(nxt)) + 3))]
            i += 2
        elif a == "-pix_fmt" and nxt == "yuv420p":
            out += ["-pix_fmt", "nv12"]       # what the Intel encoder takes; the file is still 4:2:0
            i += 2
        else:
            out.append(a)                      # x264 preset names (veryfast, medium ...) are valid for qsv too
            i += 1
    return out


_orig_run = subprocess.run


def _run(cmd, *a, **kw):
    gpu = _to_gpu(cmd) if _NVENC else None
    if gpu is None:
        return _orig_run(cmd, *a, **kw)
    check = kw.pop("check", False)
    res = _orig_run(gpu, *a, **kw)
    if res.returncode != 0:
        print("[run_sc] GPU encode failed for one ffmpeg step; redoing that step on the CPU", flush=True)
        res = _orig_run(cmd, *a, **kw)
    if check and res.returncode != 0:
        raise subprocess.CalledProcessError(res.returncode, cmd, res.stdout, res.stderr)
    return res


subprocess.run = _run

from streamclipper.cli import main  # noqa: E402

if __name__ == "__main__":
    # two pass-through commands, so plain downloads and stream-copy cuts also run under sc.ps1's guards
    if len(sys.argv) > 1 and sys.argv[1] == "ytdlp":
        import yt_dlp

        sys.exit(yt_dlp.main(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "ffmpeg":
        sys.exit(_orig_run(["ffmpeg"] + sys.argv[2:]).returncode)
    sys.exit(main())
