# Real simulator captures

Drop the six screenshots here, then:

    python3 AppStore/marketing/build_frames.py --captures AppStore/marketing/captures

That composites them into the same captioned frames and writes both required App Store
slots to `AppStore/marketing/out/{6.9,6.5}/`. Without `--captures` the script falls back to
the HTML recreations, which were only ever a stand-in for a build that could not run yet.

## Taking them

Use the **iPhone 17 Pro Max** simulator. 6.9" (440x956pt, 1320x2868px) is the required
slot size and the canvas these frames are authored at; the 6.3" iPhone 17 Pro is a
different aspect and the script will refuse it rather than stretch it.

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
| `05` | The placement sheet | No watch, no camera |
| `06` | Profile ▸ records | Streaks that survive real life |

Screenshot 01 is the awkward one: the proximity engine blanks the screen during a real
set, and the simulator has no proximity sensor anyway. Switch to **Tap** in
Settings ▸ Counting, start a set, tap a few reps in, and capture that.

The PNGs are committed. They are the source of what ships on the store page, and
regenerating the frames from a different set of captures should be a visible diff.
