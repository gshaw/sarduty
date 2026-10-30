# Mockup kit: a round's review page, from its shots.json. See docs/mockups.md.
#   python3 -I tools/mockups/review.py <round> > <round>/review.html
# A tab per shot, named by its label, with its pins as a numbered list under the picture,
# and the folder's intro.html (if any) as the first tab, with the contact sheet under it.
# Images are absolute paths, which html_render inlines.
import html
import json
import pathlib
import sys

d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
shots = json.loads((d / "shots.json").read_text())["shots"]
intro = (d / "intro.html").read_text() if (d / "intro.html").exists() else ""
if intro and (d / "shots/contact.jpg").exists():
    intro += f'<img src="{d}/shots/contact.jpg" alt="Every shot in this round">'


def narrow(k):
    """A phone-width shot: under 600 CSS pixels, read from the PNG's header."""
    png = d / "shots" / f"{k}.png"
    return png.exists() and int.from_bytes(png.read_bytes()[16:20], "big") < 1200


tabs, panes = [], []
if intro:
    tabs.append('<button data-k="intro" aria-pressed="true">Overview</button>')
    panes.append(f'<section data-k="intro">{intro}</section>')
for i, s in enumerate(shots):
    k = s.get("out", s["page"])
    first = not intro and i == 0
    name = html.escape(f'{s["id"]} · {s["title"]}' if s.get("id") else s["title"])
    tabs.append(f'<button data-k="{k}" aria-pressed="{str(first).lower()}">{name}</button>')
    pins = "".join(f"<li><span>{p}</span></li>" for p in s.get("pins", []))
    lead = f'<p class="lead">{s["lead"]}</p>' if s.get("lead") else ""
    cls = "phone" if narrow(k) else ""
    panes.append(f'<section data-k="{k}"{"" if first else " hidden"}>{lead}'
                 f'<img class="{cls}" src="{d}/shots/{k}.jpg" alt="{html.escape(s["title"])}">'
                 f'{f"<ol class=pins>{pins}</ol>" if pins else ""}</section>')

print(f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{margin:0;font-family:var(--font-sans);color:var(--foreground)}}
.bar{{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:14px}}
.bar button{{font:inherit;font-size:13px;padding:5px 11px;border-radius:999px;border:1px solid var(--border);background:transparent;color:var(--foreground);cursor:pointer}}
.bar button[aria-pressed=true]{{background:var(--primary);color:var(--primary-foreground);border-color:var(--primary)}}
p.lead{{margin:0 0 12px;font-size:14px;line-height:1.45;color:var(--muted-foreground)}}
img{{display:block;max-width:100%;border-radius:var(--radius)}}
img.phone{{max-width:340px}}
ol.pins{{margin:14px 0 0;padding:0;list-style:none;counter-reset:p;font-size:14px;line-height:1.45}}
ol.pins li{{counter-increment:p;display:grid;grid-template-columns:26px 1fr;gap:8px;margin-bottom:8px}}
ol.pins li::before{{content:counter(p);width:20px;height:20px;border-radius:50%;background:#c026d3;color:#fff;font-size:11px;font-weight:700;display:grid;place-items:center;margin-top:1px}}
table{{width:100%;border-collapse:collapse;font-size:13px;line-height:1.45}}
th,td{{text-align:left;vertical-align:top;padding:7px 10px 7px 0;border-bottom:1px solid var(--border)}}
h3{{font-size:15px;margin:18px 0 6px}} section p,section li{{font-size:14px;line-height:1.5}}
</style></head><body>
<div class="bar">{"".join(tabs)}</div>{"".join(panes)}
<script>
document.querySelectorAll('.bar button').forEach(b=>b.onclick=()=>{{
 document.querySelectorAll('.bar button').forEach(x=>x.setAttribute('aria-pressed',x===b));
 document.querySelectorAll('section').forEach(s=>s.hidden=s.dataset.k!==b.dataset.k);}});
</script></body></html>""")
