"""Measure a form's places on its page PDF (#950).

Each place in a form's `places` clause can say, in its comment, which printed label it
sits after. This finds that label on the page, measures the blank after it, and rewrites
the place's lengths in points from the page's top left. Its other options, such as fit
and size, stay as written.

    -- after 'Task Number:'                     the blank after the label
    -- after the second 'Number of Person Hours:'
    -- after 'Details of Task …:' lines 8      that blank and the lines under it
    -- under 'Equipment Used/Lost' lines 4      the blank lines under the label
    -- box after 'YES'                          the box after the label, for a tick

A blank is a run of underscores, as Word prints a form's lines. A value's baseline sits
RAISE above the line's, so its letters clear the rule.

Run it on a Mac, and read the diff before saving the form:

    uv run --with pdfplumber python -I tools/forms/find_places.py \\
      priv/forms/bcsara/task_report.txt priv/forms/bcsara/task_report.pdf
"""

import re
import sys
from statistics import median

import pdfplumber

# cspell:ignore rects -- pdfplumber's name for a page's boxes

RAISE = 1.5  # points a value's baseline sits above the printed line's
PAD = 2.0  # points between a value and each end of its blank
ORDINALS = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5}
LENGTHS = {"top", "left", "right", "bottom", "width", "indent", "pitch", "lines"}

PLACE = re.compile(r"^(?P<head>\s+\w+\s+(?P<kind>text|tick))\s+(?P<options>[^-]*?)\s*--\s*(?P<where>.+)$")
WHERE = re.compile(
    r"^(?P<how>after|under|box after)\s+(?:the (?P<nth>\w+) )?'(?P<label>[^']+)'(?:\s+lines (?P<lines>\d+))?$"
)


def main(form_path, pdf_path):
    pdf = pdfplumber.open(pdf_path)
    text = open(form_path, encoding="utf-8").read()
    out, changed, in_places = [], 0, False

    for line in text.split("\n"):
        if line and not line[0].isspace():
            in_places = line.strip() == "places"
        match = PLACE.match(line) if in_places else None
        where = WHERE.match(match["where"].strip()) if match else None

        if where:
            options = [o.strip() for o in match["options"].split(",") if o.strip()]
            page_number = next((int(o.split()[1]) for o in options if o.split()[0] == "page"), 1)
            page = Page(pdf.pages[page_number - 1])
            size = next((points(o.split()[1]) for o in options if o.split()[0] == "size"), 12.0)
            lengths = measure(page, where, match["kind"], size)
            kept = [o for o in options if o.split()[0] not in LENGTHS | set(lengths)]
            new = f"{match['head']} {', '.join(lengths_text(lengths) + kept)}  -- {match['where'].strip()}"
            changed += new != line
            print(new.strip())
            line = new

        out.append(line)

    open(form_path, "w", encoding="utf-8").write("\n".join(out))
    print(f"{changed} places changed in {form_path}", file=sys.stderr)


class Page:
    """A page's words, each with its baseline, and its boxes."""

    def __init__(self, page):
        self.height = float(page.height)
        self.words = page.extract_words(keep_blank_chars=False, return_chars=True)
        for word in self.words:
            # A char's matrix puts its baseline at f, from the page's bottom.
            word["baseline"] = median(self.height - c["matrix"][5] for c in word["chars"])
        self.rects = page.rects

    def find(self, label, nth):
        tokens = label.split()
        hits = [
            self.words[i : i + len(tokens)]
            for i in range(len(self.words) - len(tokens) + 1)
            if all(self.words[i + j]["text"] == t for j, t in enumerate(tokens))
        ]
        if len(hits) < nth:
            sys.exit(f"Found {len(hits)} of '{label}' on the page, not {nth}.")
        return hits[nth - 1]

    def blank_after(self, word):
        """The underscores right after a word on its line, as (x0, x1, baseline)."""
        line = sorted(
            (w for w in self.words if abs(w["baseline"] - word["baseline"]) < 2 and w["x0"] > word["x0"]),
            key=lambda w: w["x0"],
        )
        run = []
        for w in line:
            if not blank(w):
                break
            run.append(w)
        if not run:
            sys.exit(f"No blank after '{word['text']}'.")
        return run[0]["x0"], run[-1]["x1"], word["baseline"]

    def lines_under(self, baseline, count):
        """The next `count` lines of nothing but underscores below a baseline."""
        rows = {}
        for w in self.words:
            if blank(w) and w["baseline"] > baseline + 2:
                key = next((k for k in rows if abs(k - w["baseline"]) < 2), w["baseline"])
                rows.setdefault(key, []).append(w)
        found = [rows[k] for k in sorted(rows)][:count]
        if len(found) < count:
            sys.exit(f"Found {len(found)} lines under the label, not {count}.")
        return [(min(w["x0"] for w in r), max(w["x1"] for w in r), median(w["baseline"] for w in r)) for r in found]

    def box_after(self, word):
        """The nearest box to the right of a word, on its line."""
        middle = (word["top"] + word["bottom"]) / 2
        boxes = [r for r in self.rects if r["x0"] >= word["x1"] and r["top"] <= middle <= r["bottom"]]
        if not boxes:
            sys.exit(f"No box after '{word['text']}'.")
        return min(boxes, key=lambda r: r["x0"])


def blank(word):
    return set(word["text"]) == {"_"}


def measure(page, where, kind, size):
    label = page.find(where["label"], ORDINALS.get(where["nth"] or "first", 1))
    lines = int(where["lines"] or 1)

    if where["how"] == "box after":
        box = page.box_after(label[-1])
        side = min(box["width"], box["height"])
        return {"top": box["top"], "left": box["x0"] + (box["width"] - side) / 2, "size": side}

    if where["how"] == "after":
        first = page.blank_after(label[-1])
        rows = [first] + (page.lines_under(first[2], lines - 1) if lines > 1 else [])
    else:
        rows = page.lines_under(label[-1]["baseline"], lines)
        first = rows[0]

    left = min(r[0] for r in rows) + PAD
    lengths = {
        "top": first[2] - RAISE - size * 0.75,
        "left": left,
        "width": max(r[1] for r in rows) - PAD - left,
    }
    if first[0] + PAD > left + 1:
        lengths["indent"] = first[0] + PAD - left
    if lines > 1:
        lengths["pitch"] = (rows[-1][2] - rows[0][2]) / (lines - 1)
        lengths["lines"] = lines
    return lengths


def lengths_text(lengths):
    order = ["top", "left", "width", "indent", "pitch", "lines", "size"]
    return [f"{k} {lengths[k]}" if k == "lines" else f"{k} {lengths[k]:.1f}pt" for k in order if k in lengths]


def points(text):
    number, unit = re.match(r"([\d.]+)(\w+)", text).groups()
    return float(number) * {"pt": 1, "in": 72, "mm": 72 / 25.4}[unit]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
