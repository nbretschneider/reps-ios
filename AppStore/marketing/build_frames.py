#!/usr/bin/env python3
"""Render the App Store screenshots without a Mac or a simulator.

    python3 AppStore/marketing/build_frames.py

Lays each screen out in HTML at SwiftUI *point* values on a 440pt canvas, screenshots it
with headless Chromium, then upscales to the two required slots. The token table below is
a duplicate of Reps/DesignSystem/Theme.swift on purpose: the app cannot be run here, so
this is the only way to see the design, and the values are exact HSL copies.

Outputs to AppStore/marketing/out/{6.9,6.5}/NN-name.png.

Requires: Pillow, and the Chromium at CHROME (Playwright's copy).
"""

from __future__ import annotations

import base64
import colorsys
import pathlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "AppStore" / "marketing" / "out"
FONT_DIR = ROOT / "AppStore" / "marketing" / "fonts"

CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

# SwiftUI points. Everything below is authored at this width and scaled at the end.
CANVAS_W, CANVAS_H = 440, 956

# Both slots App Store Connect actually requires.
SLOTS = {"6.9": (1320, 2868), "6.5": (1284, 2778)}


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
      <span>43 done</span><span>60 target</span><span>Sensor</span>
    </div>
  </div>
  <div style="display:flex;justify-content:center;gap:32px;margin-bottom:64px;">
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);"></div>
    <div style="width:78px;height:78px;border-radius:999px;background:rgba(0,0,0,.35);"></div>
    <div style="width:52px;height:52px;border-radius:999px;background:rgba(0,0,0,.28);"></div>
  </div>
</div>"""


def screen_train() -> str:
    inner = f"""
<div class="body">
  <div class="title">Train</div>
  <div class="tiles">
    <div class="tile"><div class="k">Today</div><div class="v">60</div></div>
    <div class="tile"><div class="k">Week</div><div class="v">186</div></div>
    <div class="tile"><div class="k">Month</div><div class="v">757</div></div>
  </div>
  <div class="card">
    <div class="hdr">Today's session</div>
    <div style="margin:2px 0 4px;"><span class="big">60</span>
      <span class="muted"> push-ups in one set</span></div>
    <div class="cta">START TRAINING</div>
  </div>
  <div class="card">
    <div class="row">
      {ring(0.0, 72, f'<div style="font-size:20px;font-weight:700;">0</div>')}
      <div>
        <div style="font-size:20px;font-weight:700;">14 days streak</div>
        <div class="cap">Rest days don't break it.</div>
      </div>
    </div>
  </div>
  <div class="card">
    <div class="hdr">Free set</div>
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
        for i, (when, total, sets) in enumerate([
            ("Today", 60, [60]),
            ("Wednesday Aug 5", 60, [60]),
            ("Friday Aug 7", 63, [63]),
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
    reps = [0, 0, 60, 0, 62, 0, 60, 91, 0, 63, 0, 63, 30, 0, 65,
            0, 0, 0, 65, 0, 0, 68, 65, 0, 40, 68, 0, 0, 0, 0, 0]
    best = max(reps) or 1
    cells = []
    for index, value in enumerate(reps):
        day = index + 1
        fraction = value / best
        color = T["accent"] if value >= 100 else T["primary"]
        inner = f'<div style="font-size:11px;font-weight:700;">{value}</div>'
        cells.append(
            f'<div style="display:flex;flex-direction:column;align-items:center;gap:2px;">'
            f'<div style="font-size:10px;color:{T["mutedFg"]};">{day}</div>'
            f'{ring(fraction, 34, inner, color=color, width=3)}</div>'
        )
    weekdays = "".join(
        f'<div style="flex:1;text-align:center;font-size:13px;color:{T["mutedFg"]};">{d}</div>'
        for d in "MTWTFSS"
    )
    inner = f"""
<div class="body">
  <div class="title">Profile</div>
  <div class="tiles">
    <div class="tile"><div class="k">Today</div><div class="v">68</div></div>
    <div class="tile"><div class="k">Week</div><div class="v">173</div></div>
  </div>
  <div class="tiles">
    <div class="tile"><div class="k">Month</div><div class="v">760</div></div>
    <div class="tile"><div class="k">Year</div>
      <div class="v" style="color:{T['accent']};">11,954</div></div>
  </div>
  <div class="card">
    <div style="text-align:center;font-size:20px;font-weight:700;margin-bottom:12px;">
      AUGUST 2026</div>
    <div style="display:flex;margin-bottom:8px;">{weekdays}</div>
    <div style="display:grid;grid-template-columns:repeat(7,1fr);gap:8px;
                justify-items:center;">
      <div></div><div></div><div></div><div></div><div></div>
      {''.join(cells)}
    </div>
  </div>
</div>"""
    return chrome(inner, tab="Profile")


def screen_placement() -> str:
    inner = f"""
<div class="body" style="justify-content:center;padding:16px 24px;">
  <div class="card" style="text-align:center;padding:28px 20px;">
    <svg width="54" height="54" viewBox="0 0 24 24" fill="none"
         stroke="{T['primary']}" stroke-width="1.8" style="transform:rotate(90deg);">
      <rect x="6" y="2" width="12" height="20" rx="3"/>
      <circle cx="12" cy="5.2" r=".9" fill="{T['primary']}" stroke="none"/>
    </svg>
    <div style="font-size:20px;font-weight:700;margin-top:12px;">
      Phone flat on the floor, screen up, under your chest</div>
    <div class="cap" style="margin-top:8px;">
      Lower until your chest is just above it, then push back up.</div>
  </div>
  <div style="margin-top:16px;">
    <div class="hdr">Counting</div>
    <div style="display:flex;gap:8px;">
      <div style="flex:1;text-align:center;padding:12px;border-radius:12px;
                  background:{T['primary']};color:#fff;font-size:13px;font-weight:700;">
        Sensor</div>
      <div style="flex:1;text-align:center;padding:12px;border-radius:12px;
                  background:{T['muted']};color:{T['mutedFg']};font-size:13px;font-weight:700;">
        Precision</div>
      <div style="flex:1;text-align:center;padding:12px;border-radius:12px;
                  background:{T['muted']};color:{T['mutedFg']};font-size:13px;font-weight:700;">
        Tap</div>
    </div>
  </div>
  <div style="margin-top:16px;background:rgba(244,92,150,.10);border-radius:12px;
              padding:12px;">
    <div class="muted" style="color:{T['mutedFg']};">
      Put the phone on the floor under your chest. Lower until your chest is over it,
      then push.</div>
    <div style="font-size:13px;color:{T['primary']};margin-top:8px;">
      The screen going black at the bottom of each rep is the sensor working, not a bug.</div>
  </div>
  <div style="margin-top:16px;display:flex;gap:8px;">
    <div style="flex:1;padding:10px;border-radius:12px;background:{T['primary']};color:#fff;
                text-align:center;font-size:13px;font-weight:700;">One set · 60</div>
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

    inner = f"""
<div class="body" style="justify-content:center;">
  <div class="card">
    <div class="hdr">Records</div>
    {record("Best set", "91", "2026-08-06")}
    {record("Best day", "91", "2026-08-08")}
    {record("Longest streak", "41 days", "")}
    {record("All time", "11,954", "212 sessions")}
  </div>
  <div class="card" style="margin-top:16px;">
    <div class="row">
      {ring(1.0, 72, f'<div style="font-size:26px;color:{T["accent"]};">✓</div>', color=T['accent'])}
      <div>
        <div style="font-size:20px;font-weight:700;">Done for today</div>
        <div class="cap">68 push-ups logged.</div>
      </div>
    </div>
  </div>
</div>"""
    return chrome(inner, tab="Profile")


FRAMES = [
    ("01-session", screen_session, "It counts every rep", "Phone on the floor. Chest down, push up."),
    ("02-train", screen_train, "One set. Two minutes.", "Not fifteen. That's why you'll actually do it."),
    ("03-plan", screen_plan, "Got more time today?", "Multiple sets is one tap, whenever you want it."),
    ("04-profile", screen_profile, "Every number you've put in", "A month at a glance."),
    ("05-placement", screen_placement, "No watch, no camera", "The sensor your iPhone already has."),
    ("06-records", screen_records, "Streaks that survive real life", "Rest days don't break them."),
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
    if not pathlib.Path(CHROME).exists():
        raise SystemExit(f"Chromium not found at {CHROME}")
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
