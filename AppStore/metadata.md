# App Store Connect submission pack

Copy-paste ready. House rule: **no em dashes in customer-facing copy.**

---

## Name (30 char limit)

```
Reps: Push-Up Counter
```
(21 characters)

## Subtitle (30 char limit)

```
Counts with your phone
```
(21 characters)

Alternates, all within the limit:
- `Push-ups, counted for you` (25)
- `Phone on the floor. Go.` (23)

## Primary category

Health & Fitness

## Secondary category

Sports

---

## Keywords (100 char limit, comma separated, no spaces after commas)

```
pushup,push up,pushups,counter,rep counter,calisthenics,bodyweight,strength,workout,tracker,100
```
(94 characters)

Notes on what is deliberately absent: the app name's own words (`reps`) are indexed from
the name field already and repeating them wastes characters. `free` and `best` are
disallowed. Plurals of an indexed singular are matched automatically, but `pushup` and
`push up` are genuinely different search terms and both earn their place.

---

## Promotional text (170 char limit, editable without a new build)

```
Your iPhone already has the sensor. Put it on the floor under your chest, and Reps counts every rep out loud while your music keeps playing.
```
(139 characters)

---

## Description

```
Put your iPhone on the floor, screen up, under your chest. Lower until your chest is over
it, then push. That is a rep, and Reps counted it.

No watch. No chest strap. No camera pointed at you. The proximity sensor already in your
iPhone does the whole job, which means it works in a dark room, costs nothing in battery,
and never asks for a permission.

COUNTS OUT LOUD

The screen goes dark at the bottom of every rep, because your chest is on top of it. So
Reps speaks the count instead. Your music keeps playing underneath, ducking just enough
that you hear the number and then it comes back.

TELLS YOU WHAT TO DO

Reps starts by asking one question: how many push-ups can you do in a row? Everything
after that is built from your answer. Five sets, scaled to you, stepping up as you finish
them and backing off when you do not. Two sessions in a row you could not complete and the
load comes down by itself. No spreadsheet, no guessing.

Prefer a published program? The classic six week hundred push-up table and the prison
ladder are both here, reproduced exactly as written.

Prefer nothing at all? Set a number for the day and split it however you like.

A STREAK THAT SURVIVES REAL LIFE

Rest days do not break your streak. They are the plan working, not a day you missed. And
today never breaks it until today is actually over, so opening the app in the morning does
not show you a zero you have not earned yet.

Stopping at 22 of 30 records 22 of 30. A short set is a real result, and the plan uses it.

NO SOCIAL FEATURES

No leaderboards. No friend requests. No bot rival doing 600 push-ups a day. The only
person in this app is you.

PRECISION MODE

On iPhones with Face ID, Reps can use the depth camera instead. The screen stays on and
every rep gets a real depth score, so a set of shallow reps looks different from a set of
full ones. Nothing is recorded and no image ever leaves your iPhone.

EVERYTHING STAYS ON YOUR IPHONE

No account. No server. No sync. No analytics. Nothing to sign up for and nothing to leak.
Sessions can be written to Apple Health if you want them to count toward your rings, and
exported as a spreadsheet whenever you like.

FREE FOREVER

Rep counting, free sets, the daily goal, your streak and the last 30 days of history are
free and always will be.

Reps Pro adds the adaptive plan, the published programs, your full history and charts,
Precision mode, widgets, Apple Health, and export.
```

---

## What's New (first release)

```
First release. Put your phone on the floor and find out how many you can do.
```

---

## Support and marketing URLs

- Support URL: `https://gradedays.com/reps/support`
- Marketing URL: `https://gradedays.com/reps`
- Privacy policy URL: `https://gradedays.com/reps/privacy` (required, even with no data collection)

---

## Age rating

4+. No objectionable content of any kind.

---

## App Privacy answers

**Do you or your third-party partners collect data from this app?** → **No.**

That answer is true and worth protecting. It stops being true the moment any analytics SDK,
crash reporter, or ad network is added, so do not add one without changing this page first.

- Data collected: none
- Data linked to the user: none
- Data used to track the user: none
- `PrivacyInfo.xcprivacy` in both targets: tracking false, no tracking domains, no collected
  data types, no required-reason APIs

Note for the reviewer if asked about HealthKit: Reps **writes** workouts and never reads
health data. The read entitlement string exists only because HealthKit's authorization API
requires the pair.

---

## In-app purchases

| Product | ID | Type | Price tier | Trial |
|---|---|---|---|---|
| Reps Pro (Annual) | `com.gradedays.reps.pro.annual` | Auto-renewable | 29.99/yr | 3 days free |
| Reps Pro (Monthly) | `com.gradedays.reps.pro.monthly` | Auto-renewable | 4.99/mo | 3 days free |
| Reps Pro (Lifetime) | `com.gradedays.reps.pro.lifetime` | Non-consumable | 49.99 | n/a |

Subscription group: `Reps Pro`. Annual is the default selection on the paywall.

**Display names must match the paywall**, which reads them off the product rather than
hardcoding, so whatever is typed into App Store Connect is what the user sees.

Review notes for IAP: the paywall is reachable from Profile ▸ Reps Pro and appears once
after onboarding. It is always dismissible, and the app is fully functional without it.

---

## Review notes

```
Reps counts push-ups using the iPhone's proximity sensor. To test it in the simulator,
choose "Tap" as the counting engine on the setup screen that appears after pressing START
TRAINING; each tap on the screen registers one rep. The proximity sensor and Precision
mode both need a physical device.

Expected behaviour on a device: the screen turns off while the sensor is covered. That is
iOS's normal proximity behaviour, not a crash. The app speaks the count so the user does
not need to see the screen.

The app has no account, no server and no network calls other than StoreKit.
```

---

## Screenshot slots

Rendered by `python3 AppStore/marketing/build_frames.py`. Six frames, in this order:

1. **The active set.** The full-bleed magenta gradient with a huge TO GO number. This is
   the one that has to earn the tap, and it is the only screen that looks like nothing else
   in the category.
2. **Train tab.** Today's session, the set pips, START TRAINING.
3. **Plan tab.** The block ring, the anchor, the upcoming schedule.
4. **Profile.** The month grid of rings.
5. **Placement.** Phone on the floor, and the sentence about the screen going dark.
6. **Records and streak.**

Sizes: 6.9" (1320x2868) and 6.5" (1284x2778). Both are required; everything else is
derived by App Store Connect.
