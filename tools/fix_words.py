"""Give zero-length or near-zero transcript words a real duration, so every spoken word can be captioned.

Words whose gaps are tiny form a run; each run's time span is shared out by word length (and grown a little,
never into the next run). Usage: fix_words.py <clip.json or spec json>   (edits the file in place)
"""
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
ws = d["words"]
runs, cur = [], [0]
for i in range(1, len(ws)):
    if ws[i]["s"] - ws[i - 1]["e"] <= 0.05:
        cur.append(i)
    else:
        runs.append(cur); cur = [i]
runs.append(cur)
fixed = 0
for k, r in enumerate(runs):
    if all(ws[i]["e"] - ws[i]["s"] >= 0.06 for i in r):
        continue
    a = ws[r[0]]["s"]
    nxt = ws[runs[k + 1][0]]["s"] if k + 1 < len(runs) else ws[r[-1]]["e"] + 0.4
    b = min(nxt - 0.01, max(ws[r[-1]]["e"], a + 0.14 * len(r)))
    weights = [len(ws[i]["w"]) + 2 for i in r]
    t = a
    for i, wt in zip(r, weights):
        dur = (b - a) * wt / sum(weights)
        ws[i]["s"], ws[i]["e"] = round(t, 3), round(t + dur, 3)
        t += dur
    fixed += 1
json.dump(d, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
short = [w for w in ws if w["e"] - w["s"] < 0.05]
print(f"{p}: re-timed {fixed} runs; words still under 0.05 s: {len(short)}")
