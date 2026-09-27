# Real simulator captures

> **These six are stale.** They were taken before the Pro card stopped advertising
> Precision mode as paid, before records printed real dates, and before demo data trained
> seven days a week, so all three of those bugs are visible in them. `05-placement` is
> also unusable: the simulator had no TrueDepth camera and no proximity sensor, so the
> engine picker offered Tap alone and the sheet advertised a manual tap counter.
>
> What ships is rendered from the HTML recreations in `build_frames.py`, which are kept
> current with the app. Do not pass `--captures` at this directory without retaking them
> first.

Drop the six screenshots here, then:

    python3 AppStore/marketing/build_frames.py --captures AppStore/marketing/captures

That composites them into the same captioned frames and writes both required App Store
slots to `AppStore/marketing/out/{6.9,6.5}/`. Without `--captures` the script falls back to
the HTML recreations, which were only ever a stand-in for a build that could not run yet.

## Taking them

Use the **iPhone 17 Pro Max** simulator. 6.9" (440x956pt, 1320x2868px) is the required
slot size and the canvas these frames are authored at, so a capture from it is composited
at native resolution with no resampling.

A 6.3" capture is not refused — every recent portrait iPhone is within a rounding error of
the same aspect — but it is 1206px wide and gets upscaled, so the script warns. What it
does refuse is anything that is not a full screen: a window shot with chrome in it, a crop,
a landscape frame.

Fill the app with history first: **Settings ▸ Debug ▸ Fill with demo data** (debug builds
only). A fresh install screenshots as a wall of zeros.

`⌘S` in the simulator saves a full-resolution capture to the Desktop. Files are matched to
frames by their leading number, so `01.png` or `01-session.png` both work.

| File | Screen | Caption it gets |
|---|---|---|
| `01` | An active set, mid-session, gradient background | It counts every rep |
| `02` | Train tab, today's single set | One set. Two minutes. |
| `03` | Plan tab, showing the sets control | Got more time today? |
| `04` | Profile tab, month grid | Every number you've put in |
| `05` | The placement sheet | No watch, no wearables |
| `06` | Profile ▸ records | Streaks that survive real life |

Screenshot 01 is the awkward one: the simulator has neither a TrueDepth camera nor a
proximity sensor, so no engine can count there. Switch to **Tap** in Settings ▸ Counting,
start a set, tap a few reps in, and capture that. The session screen looks identical
whichever engine is running, apart from the pill at the bottom.

The PNGs are committed. They are the source of what ships on the store page, and
regenerating the frames from a different set of captures should be a visible diff.
