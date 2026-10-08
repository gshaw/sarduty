# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools[woff]"]
# ///
# cspell:ignore cmap ntos instancer wght BBBBHHII -- fontTools names, the weight axis, a struct format
"""Draws the SAR Duty logo files (#79) from the app's own IBM Plex Sans, as outlines.

    uv run assets/brand/draw_logo.py

Writes the SVGs, then exports the PNGs with headless Chrome. The style guide's Logo page
says where each file is used.
"""

import struct
import subprocess
import tempfile
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[2]
IMAGES = ROOT / "priv/static/images"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# The top bar's colours: --nav, --accent, white.
NAVY = "#13243a"
AMBER = "#ffb81c"
WHITE = "#ffffff"

font = instantiateVariableFont(TTFont(ROOT / "priv/static/fonts/ibm-plex-sans-latin.woff2"), {"wght": 700})
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
UPM = font["head"].unitsPerEm
CAP = font["OS/2"].sCapHeight / UPM


def ink(s):
    """Ink left edge and width of s at size = UPM, and the advance of each glyph."""
    pen, x, advances = BoundsPen(glyphs), 0, []
    for c in s:
        g = glyphs[cmap[ord(c)]]
        g.draw(TransformPen(pen, (1, 0, 0, 1, x, 0)))
        advances.append(g.width)
        x += g.width
    xmin, _, xmax, _ = pen.bounds
    return xmin, xmax - xmin, advances


def text(s, size, left, baseline, fill):
    """A path for s whose ink starts at left and sits on baseline."""
    xmin, _, advances = ink(s)
    scale = size / UPM
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
    x = left - xmin * scale
    for c, a in zip(s, advances):
        glyphs[cmap[ord(c)]].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        x += a * scale
    return f'<path fill="{fill}" d="{pen.getCommands()}"/>'


def centred(s, size, baseline, fill, cx=512):
    return text(s, size, cx - ink(s)[1] * size / UPM / 2, baseline, fill)


def size_for_width(s, width):
    return width * UPM / ink(s)[1]


def svg(body, width=1024, height=1024, rx=128):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img">'
        f'<title>SAR Duty</title><rect width="{width}" height="{height}" rx="{rx}" fill="{NAVY}"/>'
        f"{body}</svg>\n"
    )


def stacked():
    """SAR over DUTY, each sized to the same ink width, centred as a block."""
    width, gap = 620, 68
    sar, duty = size_for_width("SAR", width), size_for_width("DUTY", width)
    top = 512 - (CAP * sar + gap + CAP * duty) / 2
    return centred("SAR", sar, top + CAP * sar, WHITE) + centred(
        "DUTY", duty, top + CAP * sar + gap + CAP * duty, AMBER
    )


def monogram():
    """SD for 32 px and below: S white, D amber."""
    return centred("S", 520, 700, WHITE, 350) + centred("D", 520, 700, AMBER, 682)


def png(svg_path, out, width, height):
    """Export with headless Chrome, transparent outside the tile."""
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(
            f'<style>html,body{{margin:0;background:transparent}}img{{display:block}}</style>'
            f'<img src="{svg_path.as_uri()}" width="{width}" height="{height}">'
        )
        shot = Path(tmp) / "shot.png"
        subprocess.run(
            [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
             "--default-background-color=00000000", f"--window-size={width},{height}",
             f"--screenshot={shot}", page.as_uri()],
            check=True, capture_output=True,
        )
        out.write_bytes(shot.read_bytes())


def ico(pngs, out):
    """favicon.ico holding PNG images, which every current browser reads."""
    header = struct.pack("<HHH", 0, 1, len(pngs))
    offset, entries, data = 6 + 16 * len(pngs), b"", b""
    for size, path in pngs:
        blob = path.read_bytes()
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(blob), offset + len(data))
        data += blob
    out.write_bytes(header + entries + data)


if __name__ == "__main__":
    files = {
        "sarduty-logo.svg": svg(stacked()),
        "sarduty-logo-square.svg": svg(stacked(), rx=0),
        "sarduty-favicon.svg": svg(monogram()),
    }
    for name, body in files.items():
        (IMAGES / name).write_text(body)

    png(IMAGES / "sarduty-logo-square.svg", IMAGES / "sarduty-logo-square.png", 1024, 1024)
    png(IMAGES / "sarduty-logo-square.svg", IMAGES / "apple-touch-icon.png", 180, 180)
    png(IMAGES / "sarduty-logo.svg", IMAGES / "sarduty-logo-96.png", 96, 96)
    png(IMAGES / "sarduty-logo.svg", ROOT / "priv/apple/sarduty_logo.png", 660, 660)
    with tempfile.TemporaryDirectory() as tmp:
        sizes = []
        for size in (16, 32, 48):
            path = Path(tmp) / f"{size}.png"
            png(IMAGES / "sarduty-favicon.svg", path, size, size)
            sizes.append((size, path))
        ico(sizes, ROOT / "priv/static/favicon.ico")
    print("Drew", ", ".join(files), "and the PNGs")
