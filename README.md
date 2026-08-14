# Reps

A push-up trainer for iPhone that counts your reps without a wearable, a camera, or a
subscription to find out how many you did.

Put the phone on the floor, screen up, under your chest. Lower until your chest is over it,
then push. The proximity sensor already in your iPhone sees your chest arrive and leave, and
that is a rep.

**No server, no account, no network calls** except the App Store.

## Why it exists

Every push-up app in the store is a rep counter wrapped in a social network. Leaderboards,
friend requests, a bot rival who does 634 push-ups a day and never gets tired. None of that
makes anyone stronger.

Reps is built around one question: **what do I do today, and did I do it?** Three tabs, and
two of them are just answering that.

- **Train** tells you today's number and counts it.
- **Plan** decides what those sets are, and changes them when you get better or worse.
- **Profile** is every number you have ever put in.

## How the counting works

Three engines, one interface:

- **Sensor** (default) — the proximity sensor. Binary, about 2–5 cm deep, which is a
  feature: it only reads "down" when your chest is genuinely down, so a half rep does not
  count at all. No permission, no battery cost, works in a dark room. The screen goes black
  at the bottom of each rep, which is the sensor working.
- **Precision** — TrueDepth face tracking. The screen stays on and every rep gets a real
  depth score, so a set of shallow reps looks different from a set of full ones. Nothing is
  recorded and no image leaves the device.
- **Tap** — one tap, one rep. Always there for when a thick case hoods the sensor.

Because the screen is dark at the bottom of every rep in Sensor mode, **the count is spoken
out loud**. Your music keeps playing underneath it.

## Design principles

- **A rest day does not break your streak.** It is the plan working, not a missed day. Rest
  days leave the numerator *and* the denominator of every average.
- **Today does not break your streak until it is over.** Opening the app in the morning
  should not show you a zero you have not earned yet.
- **One set by default.** Five sets with rest between them is fifteen minutes, and most
  people have two. Reps asks for one working set to a number. If you want it split into
  three, that is one tap on the Plan tab, the placement screen, or Settings.
- **A short set is a real result.** Stopping at 22 of 30 records 22 of 30, and the plan uses
  it — two of those in a row and the load comes down.
- **No leaderboards, no friends, no bot rival.** The only person in this app is you.
- **The paywall is always dismissible.** Counting, your adaptive plan, free sets, your
  streak and the last 30 days are free forever. Pro is the published programs, the full
  history, Precision mode, widgets and Health.

## Layout

```
Reps/           app target: SwiftUI views, the single store, counting engines, App Intents
RepsKit/        local SPM package: models, rep machines, plan engine, stats, persistence
RepsWidget/     home screen, Lock Screen, and Control Center widgets
RepsTests/      simulator-hosted tests
scripts/        icon generation and the release preflight
```

The interesting logic — the rep state machines, the plan engine, streak arithmetic, the
persistence invariants — is all in `RepsKit` and tests in about a second with `swift test`,
no simulator needed. The machines are pure functions over sample streams, so they are tested
against synthetic sensor traces rather than against a phone on a floor.

## Building

Requires Xcode 16+, iOS 18 SDK, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate      # Reps.xcodeproj is generated and gitignored
cd RepsKit && swift test
```

See `CLAUDE.md` for the counting rules and the persistence invariants — the widget writes
data, and there are three rules that keep that safe.
