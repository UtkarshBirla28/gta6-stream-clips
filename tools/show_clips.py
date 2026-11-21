"""Print each discovered clip with its spoken words, so the picks can be judged by reading."""
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
print("keys:", sorted(d.keys()))
for c in sorted(d["clips"], key=lambda c: c.get("rank", 99))[:n]:
    def t(s): s = int(s); return f"{s//3600}:{s%3600//60:02d}:{s%60:02d}"
    words = " ".join(w.get("w", "") for w in (c.get("words") or []))
    print("=" * 100)
    print(f"#{c.get('rank')} score {c.get('score')} | {t(c['start'])}-{t(c['end'])} ({c['end']-c['start']:.0f}s) | {c.get('category')} | peak {t(c.get('peak', 0))}")
    print("hook:", c.get("hook_headline"), "| title:", c.get("title"))
    print("segments:", [(round(s.get('src_s', 0), 1), round(s.get('src_e', 0), 1), s.get('kind')) for s in c.get("segments", [])])
    print("breakdown:", {k: round(v) if isinstance(v, (int, float)) else v for k, v in (c.get("breakdown") or c.get("components") or {}).items()})
    print("words:", words[:900])
