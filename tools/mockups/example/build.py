# The kit's example round (docs/mockups.md): text reminders. A switch under Account settings,
# the text on a phone, and two diagrams. Copy this folder to start a round.  python3 -I build.py
# The cast (Web.MockupSeed) and its team's abbreviated name:
# cspell:ignore CRSAR Priya Noor
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

text = sms([
    ("time", "Today 18:02"),
    ("in", "CRSAR: Rope rescue training, Thu Nov 5, 19:00. You haven't replied. Reply YES or NO.", 1),
])
m.write_frames("2-text", [("", text)])

who = table(["Member", "Text reminders", "Mobile number", "Gets"], [
    ["Cameron Ruiz", "On", "604-555-0122", "<b>Text and email</b>"],
    ["Priya Nair", "Off", "604-555-0130", "Email"],
    ["Noor Aziz", "On", "None", "Email"],
    ["Sam Rivera", "On, replied STOP", "604-555-0133", "Email"],
], cls="table-striped")
m.write("3-who", diagram(who, "What each member gets when Alex sends reminders for Rope rescue training."))

steps = flow([
    ("Alex sends reminders", "From the activity, to members who haven't replied."),
    ("SAR Duty checks each member", "Text reminders on, a mobile number, and no STOP."),
    ("Text and email", "The text says the activity and asks for YES or NO."),
    ("Cameron replies YES", "Signed up, like Send reply on the reply page."),
])
m.write("4-flow", diagram(steps))
