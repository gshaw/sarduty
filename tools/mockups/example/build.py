# The kit's example round (docs/mockups.md): a By text switch under Account settings'
# reminder switch. Copy this folder to start a round.  python3 -I build.py
import pathlib
import sys

root = next(p for p in pathlib.Path(__file__).resolve().parents if (p / "mix.exs").exists())
sys.path.insert(0, str(root / "tools/mockups"))
from mock import *  # noqa: E402,F403

m = Mock(__file__)

s = m.page("account")
s = sub(s, '<h2 class="subheading">Emails</h2>', '<h2 class="subheading">' + changed("Reminders", 1, tag="span") + "</h2>")
by_text = switch("text-coastrange", "Text reminders",
                 "Team admins at Coast Range SAR can text 604-555-0122 when you have not replied to an activity.")
s = sub(s, "</div></section>", "</div>" + new(by_text, 2, cls="fill mt-4") + "</section>")
m.write("1-account", s)
