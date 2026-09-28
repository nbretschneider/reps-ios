#!/usr/bin/env bash
#
# Release gate. Run before archiving to TestFlight.
#
#   ./scripts/preflight.sh [--skip-release]
#
# Checks a clean main, pulls, runs the package tests, verifies the app group has not
# drifted between project.yml and Swift, regenerates the Xcode project, runs the simulator
# tests, does an unsigned Release/device compile, inspects the built bundle for the things
# App Store Connect rejects uploads over, and bumps the build number.
#
# Stops before archiving. Archive from Xcode: Product > Archive > Distribute App.
#
# macOS only. Uses xcodebuild, the iOS SDK, a simulator, and BSD sed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_RELEASE=0
[[ "${1:-}" == "--skip-release" ]] && SKIP_RELEASE=1

SIM="${PREFLIGHT_SIM:-iPhone 17 Pro}"
XCODEGEN="${XCODEGEN:-$HOME/.local/bin/xcodegen}"

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&2; exit 1; }

step "Working tree"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is dirty; commit or stash first"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || fail "on '$BRANCH', expected main"
git pull --ff-only

step "Package tests"
# The rep machines, the plan engine, streaks and persistence. About a second, no simulator.
#
# Retried once somewhere else entirely, because of a macOS failure mode that has nothing
# to do with the code: codesign refuses the test bundle with "resource fork, Finder
# information, or similar detritus not allowed" when extended attributes land on the
# build products.
#
# This checkout lives under ~/Desktop, which macOS syncs to iCloud Drive by default, and
# iCloud tags everything it touches with `com.apple.fileprovider` attributes. So the
# attributes are re-applied as fast as the build writes the bundle, which is why deleting
# `.build` and building again in the same place does not help — it was tried, by hand,
# and failed identically the second time.
#
# The retry therefore builds in a scratch directory outside the synced tree, and strips
# any attributes already on the package first. A preflight that stops here sends you
# hunting for a test failure that does not exist.
if ! (cd RepsKit && swift test); then
    echo "package tests failed; retrying in a scratch directory outside the synced folder"
    rm -rf RepsKit/.build
    xattr -cr RepsKit 2>/dev/null || true
    (cd RepsKit && swift test --scratch-path "${TMPDIR:-/tmp}/repskit-build") \
        || fail "RepsKit tests failed"
fi

step "App group consistency"
# A silent mismatch here gives the widget its own empty container and looks exactly like
# data loss, so it is worth a grep rather than a debugging session.
YML_GROUP="$(grep -Eo 'group\.[a-zA-Z0-9._]+' project.yml | head -1)"
SWIFT_GROUP="$(grep -Eo 'group\.[a-zA-Z0-9._]+' RepsKit/Sources/RepsKit/Persistence/RepsRepository.swift | head -1)"
[[ -n "$YML_GROUP" ]] || fail "no app group found in project.yml"
[[ "$YML_GROUP" == "$SWIFT_GROUP" ]] \
    || fail "app group drift: project.yml has '$YML_GROUP', Swift has '$SWIFT_GROUP'"
echo "app group: $YML_GROUP"

step "StoreKit product IDs"
# A product ID that drifts between Swift and the StoreKit config does not error anywhere.
# The paywall just shows "Pricing is unavailable", which is the most common way a first
# StoreKit release goes wrong.
SWIFT_IDS="$(grep -Eo 'com\.gradedays\.reps\.pro\.[a-z0-9.]+' Reps/Stores/PurchaseStore.swift | sort -u)"
CONFIG_IDS="$(grep -Eo 'com\.gradedays\.reps\.pro\.[a-z0-9.]+' Reps.storekit | sort -u)"
[[ -n "$SWIFT_IDS" ]] || fail "no product IDs found in PurchaseStore.swift"
if [[ "$SWIFT_IDS" != "$CONFIG_IDS" ]]; then
    printf 'Swift:\n%s\n\nReps.storekit:\n%s\n' "$SWIFT_IDS" "$CONFIG_IDS" >&2
    fail "product IDs differ between PurchaseStore.swift and Reps.storekit"
fi
echo "$(echo "$SWIFT_IDS" | wc -l | tr -d ' ') product IDs agree"

step "Regenerate project"
[[ -x "$XCODEGEN" ]] || fail "xcodegen not found at $XCODEGEN (set XCODEGEN=...)"
"$XCODEGEN" generate

# Regenerating with Xcode open leaves a duplicate behind, and building the wrong one is a
# genuinely confusing half hour.
STRAY="$(find . -maxdepth 1 -name '*.xcodeproj' ! -name 'Reps.xcodeproj' -print -quit)"
[[ -z "$STRAY" ]] || fail "stray project '$STRAY' — close Xcode, delete it, and rerun"

step "App icon"
ICON="Reps/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
[[ -f "$ICON" ]] || fail "missing $ICON — run python3 scripts/make_icon.py"
# App Store Connect rejects an icon with an alpha channel, and the failure arrives by
# email an hour after the upload.
if sips -g hasAlpha "$ICON" 2>/dev/null | grep -q 'hasAlpha: yes'; then
    fail "$ICON has an alpha channel — rerun scripts/make_icon.py"
fi

step "Simulator tests"
xcodebuild test \
    -scheme Reps \
    -destination "platform=iOS Simulator,name=$SIM" \
    -only-testing:RepsTests \
    -quiet

if [[ "$SKIP_RELEASE" -eq 0 ]]; then
    step "Release build (unsigned, device)"
    xcodebuild build \
        -scheme Reps \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath .build/preflight \
        CODE_SIGNING_ALLOWED=NO \
        -quiet

    step "Bundle inspection"
    APP="$(find .build/preflight/Build/Products -maxdepth 2 -name 'Reps.app' -print -quit)"
    [[ -n "$APP" ]] || fail "could not find the built Reps.app"

    # An extension is not covered by its host app's manifest. Both need their own copy, or
    # the upload is rejected.
    [[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "app is missing PrivacyInfo.xcprivacy"
    APPEX="$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' -print -quit 2>/dev/null || true)"
    [[ -n "$APPEX" ]] || fail "widget extension was not embedded"
    [[ -f "$APPEX/PrivacyInfo.xcprivacy" ]] || fail "widget extension is missing PrivacyInfo.xcprivacy"
    [[ -f "$APP/Assets.car" ]] || fail "asset catalog was not compiled into the bundle"

    # A portrait-only app must declare UIRequiresFullScreen or the upload is rejected with
    # error 90474, demanding all four orientations "to support iPad multitasking" — even
    # with TARGETED_DEVICE_FAMILY set to iPhone. Xcode only *warns* at build time, so
    # without this check the first sign of trouble is a failed upload after a full archive.
    ORIENTATIONS="$(/usr/libexec/PlistBuddy -c 'Print :UISupportedInterfaceOrientations' \
        "$APP/Info.plist" 2>/dev/null | grep -c UIInterfaceOrientation || true)"
    FULLSCREEN="$(/usr/libexec/PlistBuddy -c 'Print :UIRequiresFullScreen' \
        "$APP/Info.plist" 2>/dev/null || echo "false")"
    if [[ "$ORIENTATIONS" -lt 4 && "$FULLSCREEN" != "true" ]]; then
        fail "portrait-only bundle without UIRequiresFullScreen; the upload will be rejected (90474)"
    fi

    echo "bundle looks right: $(basename "$APP") + $(basename "$APPEX")"
else
    step "Release build (skipped)"
fi

step "Bump build number"
CURRENT="$(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | grep -Eo '[0-9]+' | head -1)"
[[ -n "$CURRENT" ]] || fail "could not read CURRENT_PROJECT_VERSION from project.yml"
NEXT=$((CURRENT + 1))
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )$CURRENT/\1$NEXT/" project.yml
"$XCODEGEN" generate
echo "build $CURRENT -> $NEXT"

printf '\n\033[1;32mPreflight passed.\033[0m Commit the build bump, then archive in Xcode.\n'
