# Mockup kit: splice proposals into real SAR Duty pages. See docs/mockups.md.
#
#   from mock import *                         # build.py puts tools/mockups on sys.path
#   m = Mock(__file__)
#   s = m.page("account")                      # real/account.html, from the dump test
#   s = sub(s, "<h2 ...>Emails</h2>", new("<h2 ...>Reminders</h2>", 1, tag="h2"))
#   m.write("1-account", s)
import html as _html
import os
import pathlib
import re

KIT = pathlib.Path(__file__).resolve().parent


class Mock:
    """One mockup folder: real/ holds the dumped pages, pages are written beside it."""

    def __init__(self, file):
        self.dir = pathlib.Path(file).resolve().parent

    def page(self, name):
        s = (self.dir / "real" / f"{name}.html").read_text()
        s = re.sub(r' data-phx-loc="\d+"', "", s)
        # LiveView's reconnect toasts render hidden; drop them so nothing can show.
        s = re.sub(r'<div id="(client|server)-error".*?</button></div>', "", s, flags=re.S)
        return s

    def write(self, name, body, extra_css=""):
        rel = os.path.relpath(KIT, self.dir)
        doc = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
               '<meta name="viewport" content="width=device-width,initial-scale=1">'
               f'<link rel="stylesheet" href="{rel}/app.css"><link rel="stylesheet" href="{rel}/mock.css">'
               f'{"<style>" + extra_css + "</style>" if extra_css else ""}</head>'
               f'<body>{body}<script src="{rel}/mock.js"></script></body></html>')
        (self.dir / f"{name}.html").write_text(doc)
        print("wrote", name)

    def write_frames(self, name, figures):
        """A page of phones (or anything) side by side: [(caption, html), ...]."""
        figs = "".join(f"<figure><figcaption>{c}</figcaption>{h}</figure>" for c, h in figures)
        self.write(name, f'<div class="frames">{figs}</div>')
        p = self.dir / f"{name}.html"
        p.write_text(p.read_text().replace("<body>", '<body class="frame">', 1))


# ---- Editing real pages ---------------------------------------------------------

def sub(s, old, new_, count=1):
    assert old in s, f"not found: {old[:100]!r}"
    return s.replace(old, new_, count)


def cut(s, start, end, new_):
    """Replace from `start` up to (not including) `end` with `new_`."""
    i = s.index(start)
    j = s.index(end, i)
    return s[:i] + new_ + s[j:]


def before(s, anchor, html):
    return sub(s, anchor, html + anchor)


def after(s, anchor, html):
    return sub(s, anchor, anchor + html)


def between(s, start, end):
    """The text from `start` up to (not including) `end`."""
    i = s.index(start)
    return s[i:s.index(end, i)]


# ---- Marks ------------------------------------------------------------------------

TAGS = {"new": "New", "changed": "Changed", "removed": "Removed"}


def _mark_attrs(pin, kind, right=False):
    """`right` is True for a pin on the right corner, or "inset" for one inside the left edge."""
    cls = "mk" + ("" if kind == "new" else f" mk-{kind}") + {True: " pin-right", "inset": " pin-inset"}.get(right, "")
    data = f' data-pin="{pin}" data-tag="{TAGS[kind]}"' if pin else ""
    return cls, data


def new(html, pin=None, tag="div", cls="", style="", kind="new", right=False):
    """Wrap `html` in a mark. `pin` is its number in the caption list."""
    mk, data = _mark_attrs(pin, kind, right)
    classes = f"{mk} {cls}".strip()
    st = f' style="{style}"' if style else ""
    return f'<{tag} class="{classes}"{data}{st}>{html}</{tag}>'


def changed(html, pin=None, **kw):
    return new(html, pin, kind="changed", **kw)


def removed(html, pin=None, **kw):
    return new(html, pin, kind="removed", **kw)


def mark(s, opening, pin=None, kind="new", right=False):
    """Mark an element already in the page, found by the start of its opening tag,
    such as '<section id="emails"'. Adds to its class instead of wrapping it."""
    assert opening in s, f"not found: {opening[:100]!r}"
    i = s.index(opening)
    j = s.index(">", i)
    tag = s[i:j]
    mk, data = _mark_attrs(pin, kind, right)
    if ' class="' in tag:
        tag = tag.replace(' class="', f' class="{mk} ', 1)
    else:
        tag += f' class="{mk}"'
    return s[:i] + tag + data + s[j:]


def note(text):
    """A fuchsia note in the margin, for a rule the picture can't show."""
    return f'<p class="mk-note">{text}</p>'


# ---- App pieces, as the components render them ------------------------------------

def esc(t):
    return _html.escape(t, quote=False)


def btn(text, kind="", size="", extra=""):
    cls = " ".join(c for c in ["btn", kind and f"btn-{kind}", size and f"btn-{size}", extra] if c)
    return f'<button type="button" class="{cls}">{text}</button>'


def link(text, arrow=False, ext=False):
    if ext:
        return (f'<a href="#" class="link"><span class="link-text">{text}</span>'
                '<span class="icon icon-external-link icon-sm link-icon"></span></a>')
    if arrow:
        return (f'<a href="#" class="link link-arrow"><span class="icon icon-arrow-right icon-sm"></span>'
                f'<span class="link-text">{text}</span></a>')
    return f'<a href="#" class="link">{text}</a>'


def banner(kind, title, body):
    icon = {"warning": "triangle-alert", "danger": "circle-alert", "success": "circle-check"}.get(kind, "info")
    k = "" if kind == "info" else f" banner-{kind}"
    return (f'<div class="banner{k}"><div class="banner-title"><span class="icon icon-{icon}"></span>{title}</div>'
            f'<div class="banner-body">{body}</div></div>')


def warning(text):
    return f'<div class="warning-text"><span class="icon icon-triangle-alert icon-lg"></span><span>{text}</span></div>'


def hint(text, block=True):
    return f'<span class="hint{" block" if block else ""}">{text}</span>'


def switch(id, label, hint_html, on=True, disabled=False):
    """Web.CoreComponents.switch/1."""
    c = ' checked=""' if on else ""
    d = ' disabled=""' if disabled else ""
    return (f'<div class="switch-row"><div class="grow"><label for="{id}" class="block cursor-pointer font-semibold">{label}</label>'
            f'<span id="{id}-hint" class="hint block">{hint_html}</span></div>'
            f'<input type="checkbox" role="switch" id="{id}" class="switch"{c}{d}/></div>')


def table(heads, rows, right=(), cls="table-striped w-fit"):
    th = "".join(f'<th class="whitespace-nowrap{" text-right" if i in right else ""}">{h}</th>' for i, h in enumerate(heads))
    trs = "".join("<tr>" + "".join(
        f'<td data-label="{heads[i]}" class="{"text-right" if i in right else ""}">{c}</td>'
        for i, c in enumerate(r)) + "</tr>" for r in rows)
    return f'<div class="table-wrap"><table class="table {cls}"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>'


def checkbox(on=True, label=None):
    c = ' checked=""' if on else ""
    box = f'<input type="checkbox"{c}/>'
    return f'<label class="choice">{box} {label}</label>' if label else box


def marker(kind, text):
    return f'<span class="marker marker-{kind}">{text}</span>'


# ---- Phones -------------------------------------------------------------------------

def phone(screen_html, time="9:41"):
    """An iPhone around any screen."""
    return (f'<div class="phone"><div class="phone-screen"><div class="phone-status"><span>{time}</span>'
            '<span class="island"></span><span class="icons">5G <i class="batt"></i></span></div>'
            f'{screen_html}</div></div>')


def sms(items, contact="+1 (604) 555-0100", note_=None, time="9:41"):
    """A text thread on the member's phone. Items:
    ("time", "Today 18:02")  ("in", text, pin?)  ("out", text, pin?)  ("status", "Delivered")
    A pin marks that bubble new. Write links as plain text: they're underlined."""
    out = []
    for it in items:
        kind, text = it[0], it[1]
        pin = it[2] if len(it) > 2 else None
        if kind == "time":
            out.append(f'<div class="sms-time">{text}</div>')
        elif kind == "status":
            out.append(f'<div class="sms-status">{text}</div>')
        else:
            body = re.sub(r"(sarduty\.com/\S+?)(?=[.,]?(\s|$))", r'<a href="#">\1</a>', text)
            if pin:
                mk, data = _mark_attrs(pin, "new", right=(kind == "out"))
                out.append(f'<div class="sms-{kind} {mk}"{data}>{body}</div>')
            else:
                out.append(f'<div class="sms-{kind}">{body}</div>')
    head = (f'<div class="sms-head"><div class="avatar">#</div><div class="who">{contact}'
            f'{f"<small>{note_}</small>" if note_ else ""}</div></div>')
    screen = (f'<div class="sms">{head}<div class="sms-body">{"".join(out)}</div>'
              '<div class="sms-input"><span>Text Message · SMS</span></div></div>')
    return phone(screen, time)


# ---- Email --------------------------------------------------------------------------

def mail(subject, from_, to, body_html, reply_to=None):
    """One email as a mail app shows it. `body_html` is usually the mailer's own HTML."""
    rt = f"<div>Reply-To: <b>{reply_to}</b></div>" if reply_to else ""
    return (f'<div class="mail"><div class="mail-head"><div class="subject">{subject}</div>'
            f'<div>From: <b>{from_}</b></div><div>To: {to}</div>{rt}</div>'
            f'<div class="mail-body">{body_html}</div></div>')


# ---- SMS sums -------------------------------------------------------------------------

# cspell:ignore èéùìò ΦΓΛΩΠΨΣΘΞ ÄÖÑÜ abcdefghijklmnopqrstuvwxyzäöñüà
GSM7 = set("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "ÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà^{}\\[~]|€")


def sms_parts(text):
    """How many SMS a text costs: 160 GSM-7 characters, or 70 with anything else."""
    gsm = all(c in GSM7 for c in text)
    n = len(text)
    if gsm:
        return 1 if n <= 160 else -(-n // 153)
    return 1 if n <= 70 else -(-n // 67)
