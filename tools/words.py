"""Print the saved transcript words of a time range with their times: words.py <asr dir> <start s> <end s>"""
import glob, json, sys
adir, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
words = []
for f in sorted(glob.glob(adir + "/chunk_*.json")):
    words += json.load(open(f, encoding="utf-8")).get("words") or []
line, last = [], None
for w in words:
    if not (a <= w["s"] <= b):
        continue
    if last is not None and w["s"] - last > 0.8:   # a pause starts a new line
        print(" ".join(line)); line = []
    if not line:
        line.append(f"[{w['s']:.1f}]")
    line.append(w["w"])
    last = w["e"]
if line:
    print(" ".join(line), f"[ends {last:.1f}]")
