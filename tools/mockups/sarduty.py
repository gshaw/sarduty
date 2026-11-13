# SAR Duty's adapter for redline, the shared mockup kit (~/Developer/redline). See
# docs/mockups.md. redline brings marks, frames, shots, and posting; this file brings the
# app's CSS, LiveView clean-up, and the app's pieces as its components render them.
#
#   from sarduty import *          # build.py puts tools/mockups on sys.path
#   m = SarDuty(__file__)
import os
import pathlib
import re
import sys

# `redline build` already has the kit on sys.path; REDLINE_KIT points elsewhere.
sys.path.insert(0, os.environ.get("REDLINE_KIT", str(pathlib.Path.home() / "Developer/redline/kit")))
from redline import *  # noqa: E402,F403
from redline import Round  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent


class SarDuty(Round):
    """A round on dumped SAR Duty pages, drawn with the app's own CSS (app-css.sh)."""

    def __init__(self, file):
        super().__init__(file, css=[HERE / "app.css"])

    def page(self, name):
        s = super().page(name)
        s = re.sub(r' data-phx-loc="\d+"', "", s)
        # LiveView's reconnect toasts render hidden; drop them so nothing can show.
        return re.sub(r'<div id="(client|server)-error".*?</button></div>', "", s, flags=re.S)


# ---- App pieces, as SAR Duty's components render them ------------------------------

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
    """The app's table, with mobile data-labels, in place of redline's plain one."""
    th = "".join(f'<th class="whitespace-nowrap{" text-right" if i in right else ""}">{h}</th>' for i, h in enumerate(heads))
    trs = "".join("<tr>" + "".join(
        f'<td data-label="{heads[i]}" class="{"text-right" if i in right else ""}">{c}</td>'
        for i, c in enumerate(r)) + "</tr>" for r in rows)
    return f'<div class="table-wrap"><table class="table {cls}"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>'


def checkbox(on=True, label=None):
    box = f'<input type="checkbox"{" checked" if on else ""}/>'
    return f'<label class="choice">{box} {label}</label>' if label else box


def marker(kind, text):
    return f'<span class="marker marker-{kind}">{text}</span>'
