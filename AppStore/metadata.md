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
One set. Two minutes. Put your iPhone on the floor under your chest and it counts every rep out loud, while your music keeps playing.
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

Prefer nothing at all? Set a number for the day and split it however you like.

A STREAK THAT SURVIVES REAL LIFE

Rest days do not break your streak. They are the plan working, not a day you missed. And
today never breaks it until today is actually over, so opening the app in the morning does
not show you a zero you have not earned yet.

Stopping at 22 of 30 records 22 of 30. A short set is a real result, and the plan uses it.

NO SOCIAL FEATURES

No leaderboards. No friend requests. No bot rival doing 600 push-ups a day. The only
person in this app is you.

IT SCORES YOUR DEPTH

On iPhones with Face ID, the depth camera measures how far you actually lower on every
rep, so a set of shallow reps looks different from a set of full ones. Nothing is recorded,
nothing is shown, and no image ever leaves your iPhone.

No Face ID, or want the screen off? The proximity sensor counts too. Put the top of the
phone under your sternum and touch it at the bottom of each rep.

EVERYTHING STAYS ON YOUR IPHONE

No account. No server. No sync. No analytics. Nothing to sign up for and nothing to leak.
Sessions can be written to Apple Health if you want them to count toward your rings, and
exported as a spreadsheet whenever you like.

FREE FOREVER

Rep counting, your adaptive plan, free sets, the daily goal, your streak and the last 30
days of history are free and always will be.

Reps Pro adds the published programs, your full history and charts, every rep's depth score
kept over time, widgets, Apple Health, and export.
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

| Product | ID | Type | Price | Trial |
|---|---|---|---|---|
| Reps Pro (Annual) | `com.gradedays.reps.pro.annual` | Auto-renewable | $9.99/yr | 7 days free |
| Reps Pro (Monthly) | `com.gradedays.reps.pro.monthly.v2` | Auto-renewable | $1.99/mo | 7 days free |
| Reps Pro (Lifetime) | `com.gradedays.reps.pro.lifetime` | Non-consumable | $19.99 | n/a |

Subscription group: `Reps Pro`. Annual is the default selection on the paywall.

Priced deliberately low. Annual is 83 cents a month and a 58% saving over monthly, so it is
the obvious pick — which is the point, because annual subscribers churn far less. There are
no server costs behind any of this, so cheap costs nothing to sustain.

**A price can be lowered whenever you like. Raising it on existing subscribers requires
each of them to actively opt in, and most never do.** So whatever ships is effectively
permanent for everyone who signs up early. Worth being sure before the first release.

The trial is 7 days rather than 3 because Reps schedules three sessions a week: a 3-day
trial can contain a single workout, which is not enough to see the plan adapt. Seven days
is one full training week, the smallest unit that demonstrates what the app actually does.

**Display names must match the paywall**, which reads them off the product rather than
hardcoding, so whatever is typed into App Store Connect is what the user sees.

Review notes for IAP: the paywall is reachable from Profile ▸ Reps Pro and appears once
after onboarding. It is always dismissible, and the app is fully functional without it.

### Setting these up in App Store Connect

Written out in full because this is the first Reps release that takes money, and two of
these steps block people for days without making it obvious that they are the cause.

**1. Business (formerly "Agreements, Tax, and Banking") must read Active.**
Accept the **Paid Applications** agreement, add a **bank account**, and complete the **tax
forms**. Until this is Active, products do not load **even in sandbox** — and the symptom
is the paywall showing "Pricing is unavailable", which looks exactly like a code bug and is
not one. Check here first whenever products fail to appear.

**2. Apply to the Apple Small Business Program.**
Commission drops from 30% to **15%** for developers under $1M a year. It is a short form
under Business, it has to be applied for, and it is not automatic or retroactive within a
year. Missing it is the most expensive routine mistake a first release makes. At $9.99 a
year that is the difference between keeping $6.99 and keeping $8.49 per subscriber.

**3. Create the products.** IDs must match `PurchaseStore.productIDs` **exactly**, character
for character — a typo does not error anywhere, it just silently produces no products.

> **Never delete a product to rename it.** App Store Connect retires a product ID the
> moment it is created and never releases it, even for a product deleted seconds later and
> never submitted. Reference names, display names and prices are all editable in place;
> deleting is the one action that cannot be undone. This is why the monthly ID carries a
> `.v2` suffix.

- Subscription group **`Reps Pro`** first, then the annual and monthly subscriptions inside
  it. Being in one group is what lets someone switch between them and what stops them
  buying both.
- The lifetime unlock is created separately as a **non-consumable**, not in the group.
- Add the 7-day free trial as an **Introductory Offer** on each subscription.

**4. Attach a paywall screenshot to each subscription.**
Not the app's screenshots — a screenshot on the product itself, for the reviewer. Without
it the product stays in "Missing Metadata" and cannot be submitted at all.

**5. Submit the products with the first app version.**
They do not go live separately, and a version submitted without them will ship a paywall
with nothing behind it.

Payouts arrive roughly 30 to 45 days after each month closes, once Apple's minimum
threshold is met.

Locally none of this is needed: `Reps.storekit` is wired into the scheme's Run action, so
the paywall works in the simulator against fake products. See CLAUDE.md.

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

The app has no account, no server and no network calls other than StoreKit.
```

---

## Screenshot slots

Rendered by `python3 AppStore/marketing/build_frames.py`. Six frames, in this order:

1. **The active set.** The full-bleed magenta gradient with a huge TO GO number. This is
   the one that has to earn the tap, and it is the only screen that looks like nothing else
   in the category.
2. **Train tab.** Today's number, one set, START TRAINING.
3. **Plan tab.** The block ring, the anchor, the one-set / multiple-sets switch, the
   upcoming schedule.
4. **Profile.** The month grid of rings.
5. **Placement.** Phone on the floor, and the sentence about the screen going dark.
6. **Records and streak.**

Sizes: 6.9" (1320x2868) and 6.5" (1284x2778). Both are required; everything else is
derived by App Store Connect.
