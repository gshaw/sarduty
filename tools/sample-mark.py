# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
"""The SAMPLE mark over a Try a demo team's letter (#857), priv/pdf/sample-mark.png, and
the DRAFT mark over a form's PDF while forms are testing only (#950),
priv/pdf/draft-mark.png.

Our PDF library can't rotate or fade text, but it draws a PNG's transparency, so the
mark is a picture: the word in Helvetica Bold, from a letter page's top left corner to its
bottom right, in the danger red (--danger, #c2301a) at about 25%, so the text under it
reads and a black-and-white copy still shows it. Run it again after changing it:

    uv run tools/sample-mark.py           # SAMPLE
    uv run tools/sample-mark.py DRAFT     # DRAFT

Helvetica is the macOS system font, the same face the letter's text uses.
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCALE = 2  # pixels per point, so it stays sharp in print
PAGE = (612 * SCALE, 792 * SCALE)  # US letter, in points
RED = (0xC2, 0x30, 0x1A)
ALPHA = 64  # of 255
HELVETICA_BOLD = ("/System/Library/Fonts/Helvetica.ttc", 1)
WORD = sys.argv[1] if len(sys.argv) > 1 else "SAMPLE"
OUT = Path(__file__).resolve().parent.parent / f"priv/pdf/{WORD.lower()}-mark.png"

# Top left to bottom right, down the page, over the letterhead and the text below it.
angle = -math.degrees(math.atan2(PAGE[1], PAGE[0]))
# The word's height crosses the diagonal too, so 70% of it keeps the ends off the corners.
diagonal = math.hypot(*PAGE)
probe = ImageFont.truetype(HELVETICA_BOLD[0], 100, index=HELVETICA_BOLD[1])
size = round(100 * 0.7 * diagonal / probe.getlength(WORD))
FONT = ImageFont.truetype(HELVETICA_BOLD[0], size, index=HELVETICA_BOLD[1])
left, top, right, bottom = FONT.getbbox(WORD)
word = Image.new("RGBA", (right - left, bottom - top), (0, 0, 0, 0))
ImageDraw.Draw(word).text((-left, -top), WORD, font=FONT, fill=(*RED, ALPHA))
word = word.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)

page = Image.new("RGBA", PAGE, (0, 0, 0, 0))
page.alpha_composite(word, ((PAGE[0] - word.width) // 2, (PAGE[1] - word.height) // 2))
page.save(OUT, optimize=True)
print(f"{OUT} {OUT.stat().st_size // 1000} KB")
