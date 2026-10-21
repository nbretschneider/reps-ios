#!/usr/bin/env python3
"""Render the App Store screenshots without a Mac or a simulator.

    python3 AppStore/marketing/build_frames.py

Lays each screen out in HTML at SwiftUI *point* values on a 440pt canvas, screenshots it
with headless Chromium, then upscales to the two required slots. The token table below is
a duplicate of Reps/DesignSystem/Theme.swift on purpose: the app cannot be run here, so
this is the only way to see the design, and the values are exact HSL copies.

Outputs to AppStore/marketing/out/{6.9,6.5}/NN-name.png.

Requires: Pillow, and a Chromium-family browser (see CHROME_CANDIDATES).
"""

from __future__ import annotations

import base64
import calendar
import colorsys
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "AppStore" / "marketing" / "out"
FONT_DIR = ROOT / "AppStore" / "marketing" / "fonts"

# Any Chromium will do — this only ever renders self-contained HTML with an inlined font.
# Both platforms are listed because the two halves of this job happen in different places:
# the frames get authored on Linux, and the real captures get composited on the Mac that
# ran the simulator. A hardcoded path works exactly once, on whichever machine wrote it.
CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
]


def find_chrome() -> str:
    """First browser that exists, with $CHROME winning outright.

    Raises rather than returning None, and names everything it tried: a "not found"
    that lists nothing leaves you guessing at which path it wanted.
    """
    override = os.environ.get("CHROME")
    if override:
        if not pathlib.Path(override).exists():
            raise SystemExit(f"$CHROME is set to {override}, which does not exist")
        return override
    for candidate in CHROME_CANDIDATES:
        if pathlib.Path(candidate).exists():
            return candidate
    tried = "\n  ".join(CHROME_CANDIDATES)
    raise SystemExit(
        "no Chromium-family browser found. Tried:\n  " + tried
        + "\n\nInstall one, or point at it: CHROME=/path/to/chrome python3 "
        + "AppStore/marketing/build_frames.py"
    )


CHROME = ""   # resolved in main(), so importing this module never probes the filesystem

# SwiftUI points. Everything below is authored at this width and scaled at the end.
CANVAS_W, CANVAS_H = 440, 956

# Both slots App Store Connect actually requires.
SLOTS = {
    "6.9": (1320, 2868),
    "6.5": (1284, 2778),
    # The new App Store Connect UI groups slots by device ("iPhone with Dynamic Island,
    # medium display") rather than by diagonal, and a medium display takes the 6.1" and
    # 6.3" sizes. A 6.9" frame dropped there is rejected as "file dimensions are invalid",
    # which reads like a corrupt upload and is not one.
    "6.7": (1290, 2796),
    "6.3": (1206, 2622),
    "6.1": (1179, 2556),
}


def hsl(h: float, s: float, lightness: float) -> str:
    r, g, b = colorsys.hls_to_rgb(h / 360.0, lightness / 100.0, s / 100.0)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


# Exact copies of the dark-side values in Theme.swift.
T = {
    "bg": hsl(330, 12, 7),
    "card": hsl(330, 10, 11),
    "border": hsl(330, 8, 17),
    "muted": hsl(330, 8, 16),
    "fg": hsl(330, 10, 96),
    "mutedFg": hsl(330, 6, 64),
    "primary": hsl(335, 82, 64),
    "accent": hsl(152, 66, 52),
    "gradTop": hsl(335, 80, 52),
    "gradBottom": hsl(350, 82, 42),
}


def font_face() -> str:
    """Outfit, inlined. The app uses the system rounded face, which headless Chromium on
    Linux does not have; Outfit is the closest geometric match and is vendored for exactly
    this."""
    faces = []
    for weight, name in ((400, "Outfit-Regular.ttf"), (700, "Outfit-Bold.ttf")):
        data = base64.b64encode((FONT_DIR / name).read_bytes()).decode()
        faces.append(
            f"@font-face{{font-family:Outfit;font-weight:{weight};"
            f"src:url(data:font/ttf;base64,{data}) format('truetype');}}"
        )
    return "".join(faces)


BASE_CSS = """
*{margin:0;padding:0;box-sizing:border-box;}
html,body{width:%(w)spx;height:%(h)spx;overflow:hidden;}
body{background:%(bg)s;color:%(fg)s;font-family:Outfit,sans-serif;
     -webkit-font-smoothing:antialiased;}
.screen{width:%(w)spx;height:%(h)spx;position:relative;display:flex;flex-direction:column;
        overflow:hidden;background:%(bg)s;}
.statusbar{height:54px;display:flex;align-items:flex-end;justify-content:space-between;
           padding:0 28px 6px;font-size:15px;font-weight:700;}
.notch{position:absolute;top:11px;left:50%%;transform:translateX(-50%%);
       width:124px;height:34px;border-radius:17px;background:#000;}
.body{position:absolute;top:54px;left:0;right:0;bottom:0;padding:16px;
      display:flex;flex-direction:column;gap:16px;overflow:hidden;}
.body.tabbed{bottom:78px;}
.title{font-size:32px;font-weight:700;padding:4px 0 0 4px;}
.card{background:%(card)s;border:1px solid %(border)s;border-radius:16px;padding:16px;}
.card.flush{padding:0;}
.hdr{font-size:13px;font-weight:700;letter-spacing:.6px;color:%(mutedFg)s;
     text-transform:uppercase;margin-bottom:12px;}
.row{display:flex;align-items:center;gap:12px;}
.tiles{display:flex;gap:8px;}
.tile{flex:1;background:%(muted)s;border-radius:10px;padding:10px 12px;}
.tile .k{font-size:13px;color:%(mutedFg)s;}
.tile .v{font-size:20px;font-weight:700;color:%(primary)s;}
.pips{display:flex;gap:2px;}
.pip{min-width:34px;text-align:center;font-size:13px;font-weight:700;
     padding:6px 8px;border-radius:999px;background:%(muted)s;color:%(mutedFg)s;}
.pip.on{background:%(primary)s;color:#fff;}
.pip.done{background:%(accent)s;color:#fff;}
.cta{margin-top:4px;border-radius:12px;padding:16px;text-align:center;font-size:17px;
     font-weight:700;color:#fff;
     background:linear-gradient(180deg,%(gradTop)s,%(gradBottom)s);}
.muted{color:%(mutedFg)s;font-size:15px;}
.cap{color:%(mutedFg)s;font-size:13px;}
.big{font-size:56px;font-weight:700;line-height:1.05;}
.tabbar{position:absolute;left:0;right:0;bottom:0;height:78px;
        border-top:1px solid %(border)s;display:flex;align-items:flex-start;
        padding-top:10px;background:%(bg)s;}
.tab{flex:1;text-align:center;font-size:11px;color:%(mutedFg)s;}
.tab.on{color:%(primary)s;font-weight:700;}
.tab .g{display:block;height:24px;line-height:24px;margin-bottom:2px;}
.caption{position:absolute;left:0;right:0;top:70px;text-align:center;
         font-size:26px;font-weight:700;letter-spacing:-.3px;padding:0 28px;}
.caption .sub{display:block;font-size:15px;font-weight:400;color:%(mutedFg)s;margin-top:6px;}
""" % dict(T, w=CANVAS_W, h=CANVAS_H)


# The frame is composited rather than CSS-transformed. A `scale()` on an absolutely
# positioned element interacts with `transform-origin` and ancestor `overflow:hidden` in
# ways that silently cropped the phone, and a screenshot pipeline that quietly loses the
# bottom of every screen is worse than one that is a little more verbose.
#
# So: Chromium renders the screen at full size, Chromium renders the frame background and
# caption, and Pillow pastes one into the other at a rect this file computes.
DEVICE_SCALE = 0.80
DEVICE_W = round(CANVAS_W * DEVICE_SCALE)          # 352pt
DEVICE_H = round(CANVAS_H * DEVICE_SCALE)          # 765pt
DEVICE_X = (CANVAS_W - DEVICE_W) // 2              # 44pt
DEVICE_Y = 168                                     # below the caption band
DEVICE_RADIUS = 42

FRAME_CSS = """
.frame{width:%(w)spx;height:%(h)spx;position:relative;overflow:hidden;
       background:radial-gradient(120%% 62%% at 50%% 0%%, %(gradBottom)s 0%%, %(bg)s 64%%);}
.capband{position:absolute;top:0;left:0;right:0;height:164px;display:flex;
         flex-direction:column;align-items:center;justify-content:center;
         padding:0 30px;text-align:center;}
.capband h1{font-size:30px;font-weight:700;line-height:1.14;letter-spacing:-.4px;color:#fff;}
.capband p{font-size:15px;color:rgba(255,255,255,.72);margin-top:8px;line-height:1.3;}
""" % dict(T, w=CANVAS_W, h=CANVAS_H)


def ring(fraction: float, size: int, inner: str, color: str | None = None,
         width: int = 10, track: str | None = None) -> str:
    """An SVG progress ring, drawn the same way RRing draws it: round cap, -90 degrees."""
    color = color or (T["accent"] if fraction >= 1 else T["primary"])
    track = track or T["muted"]
    r = (size - width) / 2
    circumference = 2 * 3.14159265 * r
    dash = circumference * max(0.0, min(1.0, fraction))
    return f"""
<div style="position:relative;width:{size}px;height:{size}px;flex:0 0 {size}px;">
  <svg width="{size}" height="{size}" style="transform:rotate(-90deg);">
    <circle cx="{size/2}" cy="{size/2}" r="{r}" fill="none"
            stroke="{track}" stroke-width="{width}"/>
    <circle cx="{size/2}" cy="{size/2}" r="{r}" fill="none"
            stroke="{color}" stroke-width="{width}" stroke-linecap="round"
            stroke-dasharray="{dash} {circumference}"/>
  </svg>
  <div style="position:absolute;inset:0;display:flex;align-items:center;
              justify-content:center;flex-direction:column;">{inner}</div>
</div>"""


def pips(values, active=None, done=()) -> str:
    out = []
    for i, v in enumerate(values):
        cls = "pip on" if i == active else ("pip done" if i in done else "pip")
        out.append(f'<div class="{cls}">{v}</div>')
    return f'<div class="pips">{"".join(out)}</div>'


# Inline SVG rather than SF Symbols or emoji. Headless Chromium on Linux has no SF
# Symbols and only a partial emoji font, so `figure.strengthtraining.functional` and the
# like render as tofu. These are stand-ins shaped like the real symbols.
TAB_ICONS = {
    "Train": '<circle cx="5" cy="12" r="3"/><rect x="9" y="10.5" width="12" height="3" rx="1.5"/>',
    "Plan": '<rect x="3" y="5" width="18" height="16" rx="3" fill="none" stroke="currentColor" '
            'stroke-width="2"/><rect x="3" y="5" width="18" height="5" rx="2"/>',
    "Profile": '<rect x="3" y="13" width="4" height="8" rx="1"/>'
               '<rect x="10" y="7" width="4" height="14" rx="1"/>'
               '<rect x="17" y="10" width="4" height="11" rx="1"/>',
}


def chrome(inner: str, tab: str | None = None, dark_status=True) -> str:
    if tab:
        inner = inner.replace('class="body"', 'class="body tabbed"', 1)
    tabs = ""
    if tab:
        cells = "".join(
            f'<div class="tab{" on" if name == tab else ""}">'
            f'<span class="g"><svg viewBox="0 0 24 24" width="22" height="22" '
            f'fill="currentColor">{path}</svg></span>{name}</div>'
            for name, path in TAB_ICONS.items()
        )
        tabs = f'<div class="tabbar">{cells}</div>'
    status = (
        '<div class="statusbar"><span>9:41</span><span>LTE</span></div>'
        if dark_status else ""
    )
    return f'<div class="screen">{status}<div class="notch"></div>{inner}{tabs}</div>'


# One month of history, and every total on every frame is derived from it. The numbers
# used to be typed per screen, so Train claimed 60 today while Profile claimed 68 — nobody
# compares two store screenshots side by side until the one time somebody does.
#
# The variation is the point: a plan session is about 60, and the days that run higher are
# an open set stacked on top, the days that run lower are a short one. A week of identical
# bars is both a lie about how people train and a boring chart, and it puts the average
# rule flat along the top of the bars where it reads as a ceiling rather than a mean.
MONTH_DAILY = [60, 60, 85, 58, 60, 40, 62, 60, 88, 60, 55, 62, 60, 72,
               60, 45, 63, 60, 90, 61, 60, 48, 62, 84, 60, 63, 60]
TODAY_DAY = len(MONTH_DAILY)                       # 27 September 2026
WEEK_DAILY = MONTH_DAILY[-7:]
WEEK_TOTAL = sum(WEEK_DAILY)
WEEK_AVG = round(WEEK_TOTAL / 7)
MONTH_TOTAL = sum(MONTH_DAILY)
MONTH_AVG = round(MONTH_TOTAL / TODAY_DAY)
YEAR_TOTAL = 11_954

# Weekday letters for the seven-day chart, taken from the calendar rather than typed.
# Hand-typed letters put "today" on a Monday while the month grid put the 27th on a
# Sunday, which is the sort of thing that is invisible until both frames are on one page.
_MONTH_FIRST_WEEKDAY = calendar.monthrange(2026, 9)[0]                     # Monday = 0
WEEK_LETTERS = ["MTWTFSS"[(_MONTH_FIRST_WEEKDAY + TODAY_DAY - 7 + i) % 7] for i in range(7)]


def week_chart(values, letters, today_index, average) -> str:
    """The Train tab's seven-day card, drawn the way `WeekChartCard` draws it.

    One bar per day, a dashed rule at the average so every bar reads as above or below
    the line to beat, and today's weekday letter in full-strength ink. No y-axis: the
    hero number above the chart is the scale.
    """
    peak = max(values) or 1
    height = 110
    columns = "".join(
        f'<div style="flex:1;display:flex;align-items:flex-end;justify-content:center;'
        f'height:{height}px;">'
        f'<div style="width:62%;height:{max(4, round(height * v / peak))}px;'
        f'background:{T["primary"]};border-radius:3px 3px 0 0;"></div></div>'
        for v in values
    )
    labels = "".join(
        f'<div style="flex:1;text-align:center;font-size:13px;'
        f'color:{T["fg"] if i == today_index else T["mutedFg"]};'
        f'{"font-weight:700;" if i == today_index else ""}">{letter}</div>'
        for i, letter in enumerate(letters)
    )
    return f"""
    <div style="position:relative;margin-top:4px;">
      <div style="display:flex;gap:6px;align-items:flex-end;">{columns}</div>
      <div style="position:absolute;left:0;right:0;
                  bottom:{round(height * average / peak)}px;
                  border-top:1px dashed {T['mutedFg']};opacity:.55;"></div>
    </div>
    <div style="display:flex;gap:6px;margin-top:6px;">{labels}</div>"""


def scope_chart_card() -> str:
    """Profile's scope chart: the Week / Month / Year switch over a dense bar chart.

    It sits between the month grid and the records in the real tab, and both frames that
    show that tab were leaving its space empty.
    """
    peak = max(MONTH_DAILY)
    height = 124
    bars = "".join(
        f'<div style="flex:1;background:{T["primary"]};border-radius:2px 2px 0 0;'
        f'height:{max(3, round(height * value / peak))}px;"></div>'
        for value in MONTH_DAILY
    )
    scopes = "".join(
        f'<div style="flex:1;text-align:center;padding:8px;border-radius:9px;'
        f'font-size:13px;font-weight:700;'
        f'background:{T["card"] if name == "Month" else "transparent"};'
        f'color:{T["fg"] if name == "Month" else T["mutedFg"]};">{name}</div>'
        for name in ("Week", "Month", "Year")
    )
    gridlines = "".join(
        f'<div style="position:absolute;left:34px;right:0;bottom:{round(height * f)}px;'
        f'border-top:1px solid {T["border"]};"></div>'
        for f in (0.0, 0.5, 1.0)
    )
    labels = "".join(
        f'<div style="position:absolute;left:0;bottom:{round(height * f) - 7}px;'
        f'font-size:11px;color:{T["mutedFg"]};">{round(peak * f)}</div>'
        for f in (0.0, 0.5, 1.0)
    )
    return f"""
<div class="card">
  <div style="display:flex;gap:4px;background:{T['muted']};border-radius:11px;
              padding:3px;margin-bottom:14px;">{scopes}</div>
  <div style="position:relative;height:{height}px;">
    {gridlines}{labels}
    <div style="position:absolute;left:34px;right:0;bottom:0;display:flex;gap:3px;
                align-items:flex-end;">{bars}</div>
  </div>
</div>"""


# ---------------------------------------------------------------- screens


def screen_session() -> str:
    """The active set. The only screen in this category that looks like this."""
    return f"""
<div class="screen" style="background:linear-gradient(180deg,{T['gradTop']},{T['gradBottom']});">
  <div class="statusbar" style="color:#fff;"><span>9:41</span><span>LTE</span></div>
  <div class="notch"></div>
  <!-- One set, so no pip row: a lone capsule above a 150pt counter is noise. -->
  <div style="flex:1;display:flex;flex-direction:column;align-items:center;
              justify-content:center;color:#fff;">
    <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;
                color:rgba(255,255,255,.72);">TO GO</div>
    <div style="font-size:150px;font-weight:700;line-height:1;">17</div>
    <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;
                color:rgba(255,255,255,.72);">PUSH-UPS</div>
  </div>
  <div style="display:flex;justify-content:center;margin-bottom:20px;">
    <div style="background:rgba(0,0,0,.28);border-radius:999px;padding:10px 16px;
                color:#fff;font-size:13px;font-weight:700;display:flex;gap:14px;">
      <!-- Depth mode replaces the engine name with the live face distance, which is
           what the session HUD actually shows once the camera has you. -->
      <span>43 done</span><span>60 target</span><span>24 cm</span>
    </div>
  </div>
  <!-- Mute, finish set, end session. Featureless circles read as placeholders rather
       than controls, which is the one thing a store screenshot cannot afford. -->
  <div style="display:flex;justify-content:center;align-items:center;gap:32px;
              margin-bottom:64px;">
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);
                display:flex;align-items:center;justify-content:center;">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="#fff">
        <path d="M4 9v6h4l5 4V5L8 9H4z"/>
        <path d="M16.5 8.5a5 5 0 0 1 0 7" fill="none" stroke="#fff" stroke-width="2"
              stroke-linecap="round"/>
      </svg>
    </div>
    <div style="width:78px;height:78px;border-radius:999px;background:rgba(0,0,0,.35);
                display:flex;align-items:center;justify-content:center;">
      <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#fff"
           stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M5 21V4"/><path d="M5 5h13l-2.5 4L18 13H5z" fill="#fff" stroke="none"/>
        <path d="M5 5h13l-2.5 4L18 13H5z"/>
      </svg>
    </div>
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);
                display:flex;align-items:center;justify-content:center;">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff"
           stroke-width="2.4" stroke-linecap="round">
        <path d="M6 6l12 12M18 6L6 18"/>
      </svg>
    </div>
  </div>
</div>"""


def screen_finished() -> str:
    """The moment the target is reached and the set keeps running.

    The product decision this frame exists to show: reaching your number does not end the
    set. The count flips from counting down to counting up, and the accent ring is the
    burst that fires once behind it.
    """
    return f"""
<div class="screen" style="background:linear-gradient(180deg,{T['gradTop']},{T['gradBottom']});">
  <div class="statusbar" style="color:#fff;"><span>9:41</span><span>LTE</span></div>
  <div class="notch"></div>
  <div style="flex:1;display:flex;flex-direction:column;align-items:center;
              justify-content:center;color:#fff;">
    <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;
                color:{T['accent']};">FINISHED</div>
    <div style="position:relative;display:flex;align-items:center;justify-content:center;">
      <!-- The one-shot burst, caught mid-expansion. A soft glow rather than a stroked
           ring: a hard circle at this size cuts straight through the labels above and
           below it and reads as a rendering fault rather than a celebration. -->
      <div style="position:absolute;width:320px;height:320px;border-radius:999px;
                  background:radial-gradient(circle,
                      rgba(74,222,150,.34) 0%, rgba(74,222,150,.12) 52%,
                      rgba(74,222,150,0) 70%);"></div>
      <div style="position:relative;font-size:150px;font-weight:700;line-height:1;
                  color:{T['accent']};">55</div>
    </div>
    <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;
                color:rgba(255,255,255,.72);">PUSH-UPS</div>
    <div style="margin-top:16px;background:rgba(0,0,0,.28);border-radius:999px;
                padding:9px 16px;font-size:13px;font-weight:500;">
      Target hit. 7 past it.</div>
  </div>
  <div style="display:flex;justify-content:center;margin-bottom:20px;">
    <div style="background:rgba(0,0,0,.28);border-radius:999px;padding:10px 16px;
                color:#fff;font-size:13px;font-weight:700;display:flex;gap:14px;">
      <span>55 done</span><span>48 target</span><span>26 cm</span>
    </div>
  </div>
  <div style="display:flex;justify-content:center;align-items:center;gap:32px;
              margin-bottom:64px;">
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);
                display:flex;align-items:center;justify-content:center;">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="#fff">
        <path d="M4 9v6h4l5 4V5L8 9H4z"/>
        <path d="M16.5 8.5a5 5 0 0 1 0 7" fill="none" stroke="#fff" stroke-width="2"
              stroke-linecap="round"/>
      </svg>
    </div>
    <div style="width:78px;height:78px;border-radius:999px;background:rgba(0,0,0,.35);
                display:flex;align-items:center;justify-content:center;">
      <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#fff"
           stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M5 21V4"/><path d="M5 5h13l-2.5 4L18 13H5z" fill="#fff" stroke="none"/>
        <path d="M5 5h13l-2.5 4L18 13H5z"/>
      </svg>
    </div>
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);
                display:flex;align-items:center;justify-content:center;">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff"
           stroke-width="2.4" stroke-linecap="round">
        <path d="M6 6l12 12M18 6L6 18"/>
      </svg>
    </div>
  </div>
</div>"""


# A believable session: 55 reps around 27 cm, shallower at the end because that is what
# fatigue does. Bins are 5 cm wide and anchored to the data, exactly as
# `DepthStats.histogram` anchors them, so the axis runs 15 to 35 rather than 0 to 100.
DEPTH_BINS = [(15, 20, 1), (20, 25, 9), (25, 30, 33), (30, 35, 12)]
DEPTH_MEDIAN_CM = 27

# Thirty days of the same, for the Profile card: more reps, so a smoother curve, and a
# longer tail of shallow ones because a month contains some bad days.
PROFILE_DEPTH_BINS = [(15, 20, 48), (20, 25, 212), (25, 30, 684), (30, 35, 331), (35, 40, 61)]


def depth_histogram(bins, tint: str, label: str, height: int = 92) -> str:
    """`DepthHistogram`, drawn the way the app draws it: counts above, ends labelled."""
    peak = max(count for _, _, count in bins) or 1
    columns = "".join(
        f'<div style="flex:1;display:flex;flex-direction:column;align-items:center;gap:3px;'
        f'justify-content:flex-end;">'
        f'<div style="font-size:10px;font-weight:700;color:{label};">'
        f'{count if count else "&nbsp;"}</div>'
        f'<div style="width:100%;border-radius:3px;'
        f'height:{max(6, round(height * count / peak)) if count else 3}px;'
        f'background:{tint if count else tint + "24"};"></div></div>'
        for _, _, count in bins
    )
    return f"""
    <div style="display:flex;gap:4px;align-items:flex-end;height:{height + 16}px;">
      {columns}
    </div>
    <div style="display:flex;justify-content:space-between;margin-top:4px;
                font-size:10px;color:{label};">
      <span>{bins[0][0]} cm</span><span>{bins[-1][1]} cm</span>
    </div>"""


def screen_depth() -> str:
    """The post-session summary, with the depth distribution.

    Free, deliberately: this is the session you just did. What Pro sells is the history of
    these scores, not the ability to measure them.
    """
    return f"""
<div class="screen" style="background:linear-gradient(180deg,{T['gradTop']},{T['gradBottom']});">
  <div class="statusbar" style="color:#fff;"><span>9:41</span><span>LTE</span></div>
  <div class="notch"></div>
  <div style="flex:1;display:flex;flex-direction:column;align-items:center;
              justify-content:center;color:#fff;padding:0 28px;">
    <svg width="52" height="52" viewBox="0 0 24 24" fill="#fff">
      <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1 14.5-4-4 1.5-1.5 2.5 2.5
               5-5L17.5 10z"/>
    </svg>
    <div style="font-size:84px;font-weight:700;line-height:1.05;margin-top:6px;">55</div>
    <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;
                color:rgba(255,255,255,.72);">PUSH-UPS</div>

    <!-- Sits in its own panel rather than loose on the gradient. At this size a bare
         chart on a coloured field reads as four stray rectangles; a container makes it
         a chart. -->
    <div style="width:100%;margin-top:30px;background:rgba(0,0,0,.20);
                border-radius:18px;padding:18px;">
      <div style="display:flex;align-items:baseline;gap:8px;">
        <div style="font-size:36px;font-weight:700;line-height:1;">{DEPTH_MEDIAN_CM}</div>
        <div style="font-size:13px;color:rgba(255,255,255,.72);">cm median</div>
        <div style="margin-left:auto;font-size:13px;font-weight:700;color:{T['accent']};">
          &#8599; 2 cm vs last week</div>
      </div>
      <div style="margin-top:16px;">
        {depth_histogram(DEPTH_BINS, "#ffffff", "rgba(255,255,255,.78)", height=118)}
      </div>
    </div>
    <div style="font-size:12px;color:rgba(255,255,255,.72);margin-top:14px;
                text-align:center;">
      82% of full extension &middot; 55 reps measured</div>
  </div>
  <div style="padding:0 56px 64px;">
    <div style="background:#fff;color:{T['gradBottom']};border-radius:999px;
                text-align:center;padding:16px;font-size:17px;font-weight:600;">DONE</div>
  </div>
</div>"""


def settings_row(title: str, value: str, divider: bool = False) -> str:
    """A disclosure row, the way `PlanView.row` draws one."""
    border = f"border-top:1px solid {T['border']};" if divider else ""
    return f"""
    <div style="display:flex;align-items:center;justify-content:space-between;
                padding:16px;{border}">
      <div style="font-size:15px;">{title}</div>
      <div style="display:flex;align-items:center;gap:8px;color:{T['mutedFg']};">
        <span style="font-size:15px;">{value}</span>
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
             stroke="{T['mutedFg']}" stroke-width="3" stroke-linecap="round"
             stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>
      </div>
    </div>"""


def screen_goal() -> str:
    """The Plan tab's goal control: one number a day, fixed or climbing.

    The control that replaced a goal nobody could change. `dailyGoal` was hardcoded to 100
    with no editor anywhere in the app, so the one plan built around picking your number
    shipped with the number fixed.
    """
    modes = [("Fixed", "The same number every day", False),
             ("Climbing", "Goes up when you hit it", True)]
    toggle = "".join(
        f'<div style="flex:1;padding:12px;border-radius:12px;'
        f'background:{T["primary"] if on else T["muted"]};'
        f'color:{"#fff" if on else T["mutedFg"]};">'
        f'<div style="font-size:15px;font-weight:700;">{name}</div>'
        f'<div style="font-size:13px;opacity:.8;">{detail}</div></div>'
        for name, detail, on in modes
    )

    def nudge(symbol: str) -> str:
        path = ("M5 12h14" if symbol == "minus" else "M12 5v14M5 12h14")
        return (f'<div style="width:48px;height:48px;border-radius:999px;'
                f'background:{T["muted"]};display:flex;align-items:center;'
                f'justify-content:center;flex:0 0 48px;">'
                f'<svg width="18" height="18" viewBox="0 0 24 24" fill="none" '
                f'stroke="{T["primary"]}" stroke-width="2.6" stroke-linecap="round">'
                f'<path d="{path}"/></svg></div>')

    def stepper(label: str) -> str:
        return f"""
        <div style="display:flex;align-items:center;justify-content:space-between;
                    padding:10px 0;">
          <div style="font-size:15px;">{label}</div>
          <div style="display:flex;gap:2px;background:{T['muted']};border-radius:8px;
                      padding:2px 4px;">
            <span style="color:{T['primary']};font-size:17px;font-weight:700;
                         padding:0 8px;">&#8722;</span>
            <span style="color:{T['border']};">|</span>
            <span style="color:{T['primary']};font-size:17px;font-weight:700;
                         padding:0 8px;">+</span>
          </div>
        </div>"""

    inner = f"""
<div class="body">
  <div class="title">Plan</div>
  <div class="card">
    <div class="row">
      {ring(40/48, 96, f'''
        <div style="font-size:26px;font-weight:700;">40</div>''',
        color=T['primary'])}
      <div>
        <div style="font-size:20px;font-weight:700;">Climb</div>
        <div class="cap" style="margin-top:2px;">Start where you are. Every day you hit
          the number, tomorrow goes up.</div>
        <div style="font-size:13px;font-weight:700;color:{T['primary']};margin-top:8px;">
          Today: 48</div>
      </div>
    </div>
  </div>
  <div class="card">
    <div class="hdr">Daily goal</div>
    <div style="display:flex;gap:8px;">{toggle}</div>
    <div style="display:flex;align-items:center;gap:16px;margin-top:18px;">
      {nudge("minus")}
      <div style="flex:1;text-align:center;">
        <div style="font-size:44px;font-weight:700;line-height:1;">48</div>
        <div style="font-size:11px;font-weight:700;letter-spacing:1px;
                    color:{T['mutedFg']};margin-top:2px;">TODAY'S GOAL</div>
      </div>
      {nudge("plus")}
    </div>
    <div style="margin-top:10px;">
      {stepper("Step up by 2 a day")}
      {stepper("Stop at 100")}
    </div>
    <div class="cap" style="margin-top:6px;">
      Hit 48 today and tomorrow asks for 50. Miss it once and it holds. A day you skip
      counts as neither.</div>
  </div>
  <!-- The settings rows the real tab carries below the goal. Without them the screen
       ends halfway down and reads as an unfinished mockup rather than a tab. -->
  <div class="card flush">
    {settings_row("Training days", "Every day")}
    {settings_row("Switch plan", "Climb", divider=True)}
  </div>
</div>"""
    return chrome(inner, tab="Plan")


def screen_train() -> str:
    inner = f"""
<div class="body">
  <div class="title">Train</div>
  <div class="tiles">
    <div class="tile"><div class="k">Today</div><div class="v">{MONTH_DAILY[-1]}</div></div>
    <div class="tile"><div class="k">Week</div><div class="v">{WEEK_TOTAL}</div></div>
    <div class="tile"><div class="k">Month</div><div class="v">{MONTH_TOTAL:,}</div></div>
  </div>
  <div class="card">
    <div class="hdr">Last 7 days</div>
    <div style="display:flex;align-items:baseline;gap:8px;">
      <div style="font-size:40px;font-weight:700;line-height:1;">{WEEK_AVG}</div>
      <div class="cap">avg a day</div>
      <div style="margin-left:auto;font-size:13px;font-weight:700;color:{T['accent']};">
        &#8599; +8% vs last week</div>
    </div>
    {week_chart(WEEK_DAILY, WEEK_LETTERS, 6, WEEK_AVG)}
  </div>
  <div class="card">
    <div class="hdr">Today's session</div>
    <div style="margin:2px 0 4px;"><span class="big">60</span>
      <span class="muted"> push-ups in one set</span></div>
    <div class="cta">START TRAINING</div>
  </div>
  <div class="card">
    <div class="row">
      {ring(1.0, 72, f'<div style="font-size:20px;font-weight:700;">{MONTH_DAILY[-1]}</div>',
            color=T['accent'])}
      <div>
        <div style="font-size:20px;font-weight:700;">41 days streak</div>
        <div class="cap">Rest days don't break it.</div>
      </div>
    </div>
  </div>
  <div class="card">
    <div class="hdr">Open set</div>
    <div class="muted">Count push-ups with no target.</div>
  </div>
</div>"""
    return chrome(inner, tab="Train")


def screen_plan() -> str:
    rows = "".join(
        f"""<div style="display:flex;justify-content:space-between;align-items:center;
                        padding:16px;{'border-top:1px solid ' + T['border'] if i else ''}">
              <div>
                <div style="font-size:15px;font-weight:700;
                            color:{T['primary'] if i == 0 else T['fg']};">{when}</div>
                <div class="cap">{total} push-ups</div>
              </div>
              {(f'<div style="font-size:20px;font-weight:700;color:{T["primary"]};">'
                 f'{sets[0]}</div>') if len(sets) == 1 else pips(sets)}
            </div>"""
        # Consecutive days, because training days now default to all seven. While this
        # listed Mon/Wed/Fri it advertised a schedule the app no longer creates.
        for i, (when, total, sets) in enumerate([
            ("Today", 60, [60]),
            ("Tomorrow", 60, [60]),
            ("Tuesday Sep 29", 63, [63]),
            ("Wednesday Sep 30", 63, [63]),
        ])
    )
    inner = f"""
<div class="body">
  <div class="title">Plan</div>
  <div class="card">
    <div class="row">
      {ring(27/30, 96, f'''
        <div style="font-size:11px;font-weight:700;color:{T['mutedFg']};">BLOCK 3</div>
        <div style="font-size:26px;font-weight:700;">27</div>
        <div style="font-size:11px;color:{T['mutedFg']};">of 30</div>''',
        color=T['primary'])}
      <div>
        <div style="font-size:20px;font-weight:700;">Adaptive</div>
        <div class="cap" style="margin-top:2px;">Built from your max. Steps up
          when you finish, backs off when you don't.</div>
        <div style="font-size:13px;font-weight:700;color:{T['primary']};margin-top:8px;">
          Anchor: 100 max</div>
        <div class="cap" style="margin-top:6px;">One working set to a number.
          Reps raises it as you get stronger.</div>
      </div>
    </div>
  </div>
  <div class="card">
    <div class="hdr">Session</div>
    <div style="display:flex;gap:8px;">
      <div style="flex:1;padding:12px;border-radius:12px;background:{T['primary']};color:#fff;">
        <div style="font-size:15px;font-weight:700;">One set</div>
        <div style="font-size:13px;opacity:.8;">About two minutes</div>
      </div>
      <div style="flex:1;padding:12px;border-radius:12px;background:{T['muted']};
                  color:{T['mutedFg']};">
        <div style="font-size:15px;font-weight:700;">Multiple sets</div>
        <div style="font-size:13px;opacity:.8;">More volume, more time</div>
      </div>
    </div>
  </div>
  <div class="card flush">
    <div class="hdr" style="padding:16px 16px 0;">Coming up</div>
    {rows}
  </div>
</div>"""
    return chrome(inner, tab="Plan")


def screen_profile() -> str:
    # September 2026, trained every day through the 27th. Leading blanks and the
    # weekday header come from the real calendar rather than a hand-counted offset,
    # because a grid whose columns do not line up with its own header is the kind of
    # wrong that only shows up once it is on the store page.
    year, month, today = 2026, 9, TODAY_DAY
    first_weekday, days_in_month = calendar.monthrange(year, month)   # Monday = 0
    daily = MONTH_DAILY
    best = max(daily)
    cells = ['<div></div>'] * first_weekday
    for day in range(1, days_in_month + 1):
        label = f'<div style="font-size:10px;color:{T["mutedFg"]};">{day}</div>'
        if day > today:
            # A day that has not happened is not a zero. The app draws it as the same
            # dash it gives a prescribed rest day, and so does this.
            mark = (f'<div style="width:34px;height:34px;border-radius:999px;'
                    f'border:3px solid {T["muted"]};display:flex;align-items:center;'
                    f'justify-content:center;font-size:11px;color:{T["mutedFg"]};">&#8211;</div>')
        else:
            value = daily[day - 1]
            mark = ring(value / best, 34,
                        f'<div style="font-size:11px;font-weight:700;">{value}</div>',
                        color=T["primary"], width=3)
        cells.append(
            f'<div style="display:flex;flex-direction:column;align-items:center;gap:2px;">'
            f'{label}{mark}</div>'
        )
    weekdays = "".join(
        f'<div style="flex:1;text-align:center;font-size:13px;color:{T["mutedFg"]};">{d}</div>'
        for d in "MTWTFSS"
    )
    inner = f"""
<div class="body">
  <div class="title">Profile</div>
  <div class="tiles">
    <div class="tile"><div class="k">Today</div><div class="v">{MONTH_DAILY[-1]}</div></div>
    <div class="tile"><div class="k">Week</div><div class="v">{WEEK_TOTAL}</div></div>
  </div>
  <div class="tiles">
    <div class="tile"><div class="k">Month</div><div class="v">{MONTH_TOTAL:,}</div></div>
    <div class="tile"><div class="k">Year</div>
      <div class="v" style="color:{T['accent']};">{YEAR_TOTAL:,}</div></div>
  </div>
  <div class="card">
    <div style="text-align:center;font-size:20px;font-weight:700;margin-bottom:4px;">
      SEPTEMBER 2026</div>
    <div class="cap" style="text-align:center;margin-bottom:12px;">
      {MONTH_TOTAL:,} push-ups this month &middot; avg {MONTH_AVG} a day</div>
    <div style="display:flex;margin-bottom:8px;">{weekdays}</div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:8px;
                justify-items:center;">
      {''.join(cells)}
    </div>
  </div>
  {scope_chart_card()}
</div>"""
    return chrome(inner, tab="Profile")


def screen_placement() -> str:
    """Precision mode's placement, which is the opposite of the proximity one.

    Depth counting wants the camera under your face looking straight up; proximity
    wanted the top of the phone under your sternum. This frame used to show the second
    one with the engine picker highlighting Sensor, which advertised the engine that
    cannot count on any phone new enough to run the depth camera.
    """
    engines = [("Sensor", False), ("Precision", True), ("Tap", False)]
    picker = "".join(
        f'<div style="flex:1;text-align:center;padding:12px;border-radius:12px;'
        f'background:{T["primary"] if on else T["muted"]};'
        f'color:{"#fff" if on else T["mutedFg"]};font-size:13px;font-weight:700;">'
        f'{name}</div>'
        for name, on in engines
    )
    inner = f"""
<div class="body" style="justify-content:center;padding:16px 24px;">
  <!-- It is a sheet, and the real one carries a nav bar. Without it the screen reads as
       a tab, which is the one thing this screen never is. -->
  <div style="display:flex;align-items:center;justify-content:space-between;
              margin:-4px 0 4px;">
    <div style="font-size:15px;color:{T['primary']};">Cancel</div>
    <div style="font-size:15px;font-weight:700;">Get set up</div>
    <div style="width:44px;"></div>
  </div>
  <div class="card" style="text-align:center;padding:28px 20px;">
    <svg width="54" height="54" viewBox="0 0 24 24" fill="none"
         stroke="{T['primary']}" stroke-width="1.8" stroke-linecap="round">
      <path d="M4 8V6a2 2 0 0 1 2-2h2"/><path d="M16 4h2a2 2 0 0 1 2 2v2"/>
      <path d="M20 16v2a2 2 0 0 1-2 2h-2"/><path d="M8 20H6a2 2 0 0 1-2-2v-2"/>
      <path d="M9 10v1.5"/><path d="M15 10v1.5"/>
      <path d="M12 10v3.5h-1"/><path d="M9 15.5c1.8 1.2 4.2 1.2 6 0"/>
    </svg>
    <div style="font-size:20px;font-weight:700;margin-top:12px;">
      Phone flat on the floor, screen up, directly under your face</div>
    <div class="cap" style="margin-top:8px;">
      The camera should look straight up at you. It says tracking once it sees your
      face, and counting is automatic from there.</div>
  </div>
  <div style="margin-top:16px;">
    <div class="hdr">Counting</div>
    <div style="display:flex;gap:8px;">{picker}</div>
  </div>
  <div style="margin-top:16px;background:rgba(244,92,150,.10);border-radius:12px;
              padding:12px;">
    <div class="muted" style="color:{T['mutedFg']};">
      The front camera measures how far you lower on each rep and scores your depth.
      The screen stays on.</div>
  </div>
  <div style="margin-top:16px;display:flex;gap:8px;">
    <div style="flex:1;padding:10px;border-radius:12px;background:{T['primary']};color:#fff;
                text-align:center;font-size:13px;font-weight:700;">One set &middot; 60</div>
    <div style="flex:1;padding:10px;border-radius:12px;background:{T['muted']};
                color:{T['mutedFg']};text-align:center;font-size:13px;font-weight:700;">
      Multiple sets</div>
  </div>
  <div class="cta" style="margin-top:16px;">I'M READY</div>
</div>"""
    return chrome(inner)


def screen_records() -> str:
    def record(title, value, detail):
        return f"""
        <div style="display:flex;justify-content:space-between;align-items:baseline;
                    padding:12px 0;border-bottom:1px solid {T['border']};">
          <div class="muted">{title}</div>
          <div style="text-align:right;">
            <div style="font-size:15px;font-weight:700;">{value}</div>
            <div class="cap">{detail}</div>
          </div>
        </div>"""

    # Dates read as dates. The card used to print the stored day key, so a personal
    # best was dated "2026-08-06" like a row out of a database.
    inner = f"""
<div class="body" style="justify-content:center;">
  {scope_chart_card()}
  <div class="card">
    <div class="hdr">Records</div>
    {record("Best set", "91", "6 Aug 2026")}
    {record("Best day", "91", "8 Aug 2026")}
    {record("Longest streak", "41 days", "")}
    {record("All time", "11,954", "212 sessions")}
  </div>
  <!-- The Depth card, which is where the upsell used to be. There is no upsell now:
       the app has no in-app purchases, so this slot shows the thirty-day depth history
       that used to sit behind the paywall. -->
  <div class="card" style="margin-top:16px;">
    <div class="hdr">Depth</div>
    <div style="display:flex;align-items:baseline;gap:8px;">
      <div style="font-size:34px;font-weight:700;line-height:1;">26</div>
      <div class="cap">cm median</div>
      <div style="margin-left:auto;font-size:13px;font-weight:700;color:{T['accent']};">
        &#8599; 3 cm</div>
    </div>
    <div style="margin-top:10px;">
      {depth_histogram(PROFILE_DEPTH_BINS, T['primary'], T['mutedFg'], height=74)}
    </div>
  </div>
</div>"""
    return chrome(inner, tab="Profile")


# Order is the store listing's order, and the first three are what shows in search before
# anyone swipes: it counts, it does not stop you, and you pick the number. The two frames
# that sell the new work sit at 2 and 4 rather than at the end for that reason.
FRAMES = [
    ("01-session", screen_session, "It counts every rep", "Phone on the floor. Lower, push, counted."),
    ("02-finished", screen_finished, "Hit your number, keep going", "Reaching the target doesn't end your set."),
    ("03-goal", screen_goal, "Pick your number, or climb", "Fifty every day, or two more each day you hit it."),
    ("04-train", screen_train, "One set. Two minutes.", "Not fifteen. That's why you'll actually do it."),
    ("05-depth", screen_depth, "How deep you actually go", "Every rep measured, in centimetres."),
    ("06-plan", screen_plan, "Got more time today?", "Multiple sets is one tap, whenever you want it."),
    ("07-profile", screen_profile, "Every number you've put in", "A month at a glance."),
    ("08-placement", screen_placement, "No watch, no wearables", "The camera that unlocks your iPhone does it."),
    ("09-records", screen_records, "Streaks that survive real life", "Rest days don't break them."),
]


# Headless Chrome's --window-size counts browser chrome, so the *viewport* comes out
# roughly 90 CSS px shorter than the window. The screenshot is still window-sized, so the
# page silently lays out short and the bottom of every screen is simply never rendered.
# Ask for slack and crop back to the canvas.
WINDOW_SLACK = 160


def shot(html_body: str, css: str, width: int, height: int) -> Image.Image:
    """Screenshot one HTML fragment at 3x, cropped to exactly (width, height) points."""
    html = (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        + font_face() + css + "</style></head><body>" + html_body + "</body></html>"
    )
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = pathlib.Path(tmp)
        (tmp_path / "f.html").write_text(html)
        out = tmp_path / "shot.png"
        subprocess.run(
            [
                CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                "--hide-scrollbars", "--force-device-scale-factor=3",
                f"--window-size={width},{height + WINDOW_SLACK}",
                f"--screenshot={out}", f"--user-data-dir={tmp_path / 'profile'}",
                (tmp_path / "f.html").as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        image = Image.open(out).convert("RGB").crop((0, 0, width * 3, height * 3))
        if image.size != (width * 3, height * 3):
            raise SystemExit(f"expected {(width * 3, height * 3)}, got {image.size}")
        return image


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (size[0] * 2, size[1] * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size[0] * 2 - 1, size[1] * 2 - 1], radius=radius * 2, fill=255
    )
    return mask.resize(size, Image.LANCZOS)


def render(screen: Image.Image, caption: str, sub: str) -> Image.Image:
    """One marketing frame: caption band from HTML, phone screen composited in.

    `screen` is the full-bleed app screen at any resolution with the device's aspect
    ratio: either a Chromium render of the mockup HTML or a real simulator capture."""
    scale = 3
    frame = shot(
        f'<div class="frame"><div class="capband"><h1>{caption}</h1><p>{sub}</p></div></div>',
        BASE_CSS + FRAME_CSS, CANVAS_W, CANVAS_H,
    )

    box = (DEVICE_W * scale, DEVICE_H * scale)
    device = screen.resize(box, Image.LANCZOS)
    origin = (DEVICE_X * scale, DEVICE_Y * scale)
    frame.paste(device, origin, rounded_mask(box, DEVICE_RADIUS * scale))

    # A hairline bezel, because the device background and the frame background are the
    # same token and the phone would otherwise have no visible edge at all.
    ImageDraw.Draw(frame).rounded_rectangle(
        [origin[0], origin[1], origin[0] + box[0] - 1, origin[1] + box[1] - 1],
        radius=DEVICE_RADIUS * scale,
        outline=(255, 255, 255, 255),
        width=scale,
    )
    return frame


def load_captures(directory: pathlib.Path) -> dict[str, Image.Image]:
    """Real simulator captures, matched to frames by leading number.

    Name the files anything starting with the frame number: `01.png`,
    `02-train.png`, `03 whatever.PNG`. Take them in the simulator with ⌘S.

    The aspect check is deliberately loose, at 0.01. Every recent portrait iPhone lands
    within 0.001 of the 6.9" canvas — the 6.3" is 0.4600 against 0.4603 — so tightening it
    would reject captures that composite perfectly. What it is actually for is a capture
    that is not a full screen at all: a window shot with chrome in it, a crop, a landscape
    frame. Those are refused rather than stretched to fit, because a stretched screenshot
    is exactly what guideline 2.3.3 is about.

    A capture narrower than the 6.9" slot still works and is only softer, so that is a
    warning, not a refusal.
    """
    expected = CANVAS_W / CANVAS_H
    native_width = SLOTS["6.9"][0]
    captures: dict[str, Image.Image] = {}
    for name, _, _, _ in FRAMES:
        number = name.split("-")[0]
        matches = sorted(
            f for f in directory.iterdir()
            if f.suffix.lower() == ".png" and f.stem.split("-")[0].split(" ")[0] == number
        )
        if not matches:
            raise SystemExit(f"no capture for frame {name}: expected {number}*.png in {directory}")
        image = Image.open(matches[0]).convert("RGB")
        aspect = image.width / image.height
        if abs(aspect - expected) > 0.01:
            raise SystemExit(
                f"{matches[0].name} is {image.width}x{image.height} "
                f"(aspect {aspect:.3f}, expected {expected:.3f}) — not a full-screen portrait capture"
            )
        if image.width < native_width:
            print(
                f"  warning: {matches[0].name} is {image.width}px wide, upscaled to "
                f"{native_width}px — capture on the iPhone 17 Pro Max for a sharp frame"
            )
        captures[name] = image
    return captures


def main() -> None:
    global CHROME
    CHROME = find_chrome()
    print(f"chrome: {CHROME}")
    if DEVICE_Y + DEVICE_H > CANVAS_H:
        raise SystemExit("the device slot does not fit under the caption band")

    # `--captures <dir>` composites real simulator screenshots into the captioned frames
    # instead of the HTML mockups. Use it once the app runs: recreations were only ever a
    # stand-in for a build that could not exist yet.
    captures: dict[str, Image.Image] | None = None
    argv = sys.argv[1:]
    if argv and argv[0] == "--captures":
        if len(argv) < 2:
            raise SystemExit("usage: build_frames.py [--captures <directory>]")
        captures = load_captures(pathlib.Path(argv[1]))

    if OUT.exists():
        shutil.rmtree(OUT)
    for slot in SLOTS:
        (OUT / slot).mkdir(parents=True)

    for name, build, caption, sub in FRAMES:
        screen = captures[name] if captures else shot(build(), BASE_CSS, CANVAS_W, CANVAS_H)
        image = render(screen, caption, sub)
        for slot, (width, height) in SLOTS.items():
            resized = image.resize((width, height), Image.LANCZOS)
            assert resized.mode == "RGB", "App Store Connect rejects an alpha channel"
            resized.save(OUT / slot / f"{name}.png", format="PNG")
        print(f"rendered {name}")

    print(f"\nwrote {len(FRAMES) * len(SLOTS)} frames to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
