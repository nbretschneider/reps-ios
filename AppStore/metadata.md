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
One set. Two minutes. Put your iPhone on the floor under your face and it counts every rep out loud, while your music keeps playing.
```
(139 characters)

---

## Description

```
Put your iPhone on the floor, screen up, under your face. Lower toward it, push back up.
That is a rep, and Reps counted it at the bottom, where the work is.

No watch. No chest strap. No typing numbers after every set. The same camera that unlocks
your iPhone measures how far away your face is, sixty times a second. Nothing is recorded,
nothing is shown, and no image ever leaves your iPhone.

COUNTS OUT LOUD

You are mid push-up. You are not reading a screen. So Reps speaks every rep as you make
it, and your music keeps playing underneath, ducking just enough that you hear the number
before it comes back.

ONE SET, NOT FIFTEEN MINUTES

Reps starts by asking one question: how many push-ups can you do in a row? Everything after
that is built from your answer.

Most push-up apps hand you five sets with rest between them. That is fifteen minutes, and
most days you do not have fifteen minutes. So Reps gives you one working set to a number,
scaled to you, stepping up as you finish it and backing off when you do not. Two minutes on
the floor and the day is done.

Want more? Turning on multiple sets is one tap, on the Plan tab or on the screen right
before you start. Two to five sets, whenever you have the time for it.

Prefer a published program? The classic six week hundred push-up table and the prison
ladder are both here, reproduced exactly as written.

Prefer nothing at all? Set a number for the day and split it however you like. Or let it
climb: pick where you start, and every day you hit the number, tomorrow goes up by two.
Miss a day and it holds. Skip a day entirely and nothing moves. It stops at a ceiling you
choose, so it never runs away from you.

A STREAK THAT SURVIVES REAL LIFE

Rest days do not break your streak. They are the plan working, not a day you missed. And
today never breaks it until today is actually over, so opening the app in the morning does
not show you a zero you have not earned yet.

Stopping at 22 of 30 records 22 of 30. A short set is a real result, and the plan uses it.

NO SOCIAL FEATURES

No leaderboards. No friend requests. No bot rival doing 600 push-ups a day. The only
person in this app is you.

IT SCORES YOUR DEPTH

Every rep gets a depth score, in percent and in centimetres, so a set of shallow reps
looks different from a set of full ones. Not to judge you. So that when you get stronger,
you can see it.

No Face ID on your phone? The proximity sensor counts on models that have one, and tap
counting works everywhere: touch the screen with your nose at the bottom of each rep.

EVERYTHING STAYS ON YOUR IPHONE

No account. No server. No sync. No analytics. Nothing to sign up for and nothing to leak.
Sessions can be written to Apple Health if you want them to count toward your rings, and
exported as a spreadsheet whenever you like.

FREE. ALL OF IT.

No subscription, no in-app purchases, no locked features, no trial that runs out. Every
plan, every counting mode, your whole history, the depth charts, the widgets, Apple Health
and export. There is nothing to buy and nothing to upgrade to.
```

---

## What's New (first release)

```
First release. Put your phone on the floor and find out how many you can do.
```

---

## Support and marketing URLs

| Field | URL | Required |
|---|---|---|
| Privacy Policy URL | `https://nbretschneider.github.io/reps/privacy-policy.html` | **yes** |
| Support URL | `https://nbretschneider.github.io/reps/support.html` | **yes** |
| Marketing URL | `https://nbretschneider.github.io/reps/` | no |

### Hosting

Same arrangement as Grams: a separate **public** repo, `nbretschneider/reps`, holding the
three files at its root and served by GitHub Pages. Not gradedays.com — that domain is a
full Vite/Express app, so putting static pages on it is a deployment rather than a copy,
and a submission should never wait on one.

The source of truth is `AppStore/web/` in this repo. Edit here, copy to the pages repo, so
the pages and the submission pack cannot drift apart.

To publish:

1. github.com ▸ **New repository** ▸ name `reps` ▸ **Public** ▸ Create.
2. Upload `index.html`, `privacy-policy.html`, `support.html`, `README.md` from
   `AppStore/web/` to the root.
3. That repo's **Settings ▸ Pages** ▸ Source: *Deploy from a branch*, branch `main`,
   folder `/ (root)` ▸ Save. Live in a minute or two.

**The privacy URL must resolve before you submit** — App Store Connect fetches it. The URLs
can be changed later without shipping a new build.

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

**There are none.** The app is free in full: every plan, every counting engine, the whole
history, the depth analytics, widgets, Health sync and CSV export.

This is what makes the submission short. A free app with no in-app purchases does **not**
need the Paid Applications agreement, a bank account, tax forms, the Small Business
Program, product listings, or a review screenshot per product — and there is no
"submit the products with the app or they wait forever" trap, because there are no
products. The free-app agreement is already accepted on every account.

The subscription that used to be specified here (three tiers, `Reps Pro` group, 7-day
trial) was built and then removed. If it ever comes back it is a new decision, not a
restoration: anything free today that moves behind a paywall tomorrow is taken away from
everyone already using it.

Pricing: **Free**, all territories, no IAP. App Store Connect ▸ Pricing and Availability.

---

## Review notes

```
Reps counts push-ups with the phone on the floor. By default it uses TrueDepth face
tracking to measure how far the user lowers; the front camera is used only for distance,
no image is recorded, shown, or transmitted.

To test in the simulator, choose "Tap" as the counting engine on the setup screen that
appears after pressing START TRAINING; each tap registers one rep. Face tracking and the
proximity sensor both need a physical device.

If you switch the engine to "Sensor" on a device, expect the screen to turn off while the
proximity sensor is covered. That is iOS's normal proximity behaviour, not a crash, and
the app speaks the count so the screen is not needed. Settings > Counting has a Camera
check and a Sensor check that show each sensor's raw state if you want to see them
directly.

The app has no account, no server, no network calls and no in-app purchases.
```

---

## Screenshot slots

Rendered by `python3 AppStore/marketing/build_frames.py`. Nine frames, in this order.

Order is the listing's order, and the first three matter most: search results show three
before anyone swipes. So it counts, it does not stop you, and you pick the number.

1. **The active set.** The full-bleed magenta gradient with a huge TO GO number. This is
   the one that has to earn the tap, and it is the only screen that looks like nothing else
   in the category.
2. **Target hit.** The count flipped to counting up, past the number. Reaching your target
   does not end the set, which is the thing competitors get wrong.
3. **The goal control.** Fixed or Climbing, and the number. The feature that answers
   "where does this number even come from".
4. **Train tab.** The seven-day chart, today's number, START TRAINING.
5. **Depth.** The post-session distribution in centimetres. Free, because it is the session
   you just did; the Profile tab carries a thirty-day version of the same chart.
6. **Plan tab.** The block ring, the anchor, the one-set / multiple-sets switch, the
   upcoming schedule.
7. **Profile.** The month grid of rings.
8. **Placement.** Phone on the floor, and the sentence about the screen going dark.
9. **Records and streak.**

Sizes: 6.9" (1320x2868) and 6.5" (1284x2778). Both are required; everything else is
derived by App Store Connect. Apple allows ten, so there is one slot spare.

**Keep these in step with what shipped.** The frames are mockups, not captures, so nothing
forces them to match the build — a frame can advertise a screen the installed app does not
have, and nobody finds out until a reviewer does.
