# Mockup kit: the Markdown for an issue or PR body, from a round's shots.json. See
# docs/mockups.md.
#   python3 -I tools/mockups/body.py <round> > <round>/body.md
#   python3 -I tools/mockups/body.py <round> --attach     # the matching --attach flags
#   gh issue view <n> --json body -q .body | python3 -I tools/mockups/body.py --attached
# The contact sheet first, if there is one, then each shot: its label and title, its lead,
# the picture, and its pins as a numbered list. A phone-width shot is an <img width="320">,
# because GitHub draws every image as wide as the column, and a 2x phone shot runs about
# five screens tall. Paths are ./shots/…, which gh --attach uploads. gh rewrites only
# ![…](./…), and appends an <img>'s upload to the end instead: --attached moves each one
# back into its tag, matched by alt text.
import html
import json
import pathlib
import re
import shlex
import sys

if sys.argv[1:] == ["--attached"]:
    body = sys.stdin.read()
    for alt, url in re.findall(r"^!\[([^\]]*)\]\((https://github\.com/user-attachments/[^)]+)\)\s*$", body, re.M):
        tag = re.compile(rf'(<img [^>]*alt="{re.escape(html.escape(alt, quote=True))}"[^>]*src=")\./[^"]+(")')
        if tag.search(body):
            body = tag.sub(lambda m: m.group(1) + url + m.group(2), body, count=1)
            body = re.sub(rf"\n*^!\[{re.escape(alt)}\]\({re.escape(url)}\)\s*$", "", body, count=1, flags=re.M)
    print(body.rstrip())
    sys.exit()

d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
data = json.loads((d / "shots.json").read_text())


def narrow(k):
    """A phone-width shot: under 600 CSS pixels, read from the PNG's header."""
    png = d / "shots" / f"{k}.png"
    return png.exists() and int.from_bytes(png.read_bytes()[16:20], "big") < 1200


def posted(k):
    """The file to post: the JPG when shots.mjs kept one because it was smaller, else the PNG."""
    return f"{k}.jpg" if (d / f"shots/{k}.jpg").exists() else f"{k}.png"


def md(text):
    """Captions are written as HTML for the review page; GitHub reads them as Markdown."""
    return re.sub(r"</?b>", "**", text)


if sys.argv[2:] == ["--attach"]:
    files = [("contact", "Every shot in this round")] if data.get("contact") else []
    files += [(s.get("out", s["page"]), f'{s["id"]} · {s["title"]}' if s.get("id") else s["title"]) for s in data["shots"]]
    print(" ".join("--attach " + shlex.quote(f"./shots/{posted(k)}#{alt}") for k, alt in files if (d / f"shots/{k}.png").exists()))
    sys.exit()

out = []
if data.get("contact") and (d / "shots/contact.png").exists():
    out.append(f"![Every shot in this round](./shots/{posted('contact')})")
for s in data["shots"]:
    k = s.get("out", s["page"])
    name = f'{s["id"]} · {s["title"]}' if s.get("id") else s["title"]
    alt = html.escape(name, quote=True)
    out.append(f"**{name}**" + (f'\n\n{md(s["lead"])}' if s.get("lead") else ""))
    if narrow(k):
        out.append(f'<img width="320" alt="{alt}" src="./shots/{posted(k)}">')
    else:
        out.append(f"![{alt}](./shots/{posted(k)})")
    if s.get("pins"):
        out.append("\n".join(f"{i}. {md(p)}" for i, p in enumerate(s["pins"], 1)))
print("\n\n".join(out))
