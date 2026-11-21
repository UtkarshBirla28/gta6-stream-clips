"""Write a StreamClipper clip spec for one hand-picked moment of a stream that was already transcribed.

    make_spec.py <asr dir> <name> <start s> <end s> <caption style> <hook headline> <spec out dir> [pad s]

- start/end are times in the full stream. The clip is snapped outward to whole words.
- The source for the render is a small slice <spec out dir>/../src/<name>.mp4 that covers
  [start - pad, end + pad] of the stream; this script prints the exact slice range to download.
- Word times in the spec are shifted to the slice's own clock.
"""
import glob
import json
import os
import sys

adir, name, a, b, style, hook, out_dir = sys.argv[1:8]
a, b = float(a), float(b)
pad = float(sys.argv[8]) if len(sys.argv) > 8 else 4.0

words = []
for f in sorted(glob.glob(os.path.join(adir, "chunk_*.json"))):
    words += json.load(open(f, encoding="utf-8")).get("words") or []
inside = [w for w in words if w["e"] > a and w["s"] < b]
if not inside:
    sys.exit("no words in that range")
start, end = min(a, inside[0]["s"]) - 0.15, max(b, inside[-1]["e"]) + 0.35
s0 = max(0.0, round(start - pad, 2))          # slice start in stream time
s1 = round(end + pad, 2)
spec = {
    "draft_name": name,
    "preset": "streamer-split-9x16",
    "source_video": f"../src/{name}.mp4",
    "start": round(start - s0, 3),
    "end": round(end - s0, 3),
    "trim_silence": True,
    "caption_style": style,
    "hook_headline": hook,
    "words": [{"w": w["w"], "s": round(w["s"] - s0, 3), "e": round(w["e"] - s0, 3)} for w in inside],
}
os.makedirs(out_dir, exist_ok=True)
path = os.path.join(out_dir, f"{name}.json")
json.dump(spec, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print(f"SPEC {path}")
print(f"SLICE {s0:g} {s1:g}")
print(f"clip {end - start:.1f}s, {len(inside)} words: " + " ".join(w["w"] for w in inside)[:300])
