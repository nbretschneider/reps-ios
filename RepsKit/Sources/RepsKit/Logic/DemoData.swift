import Foundation

/// A believable history, for screenshots.
///
/// A fresh install screenshots as a wall of zeros: an empty month grid, no streak, no
/// records, a flat chart. That is an accurate picture of a brand new account and a useless
/// picture of the app, so the App Store frames need a seeded device.
///
/// Deliberately pure and deterministic. It lives in RepsKit rather than in a script so it
/// builds the *real* types — a hand-written `state.json` that decodes even slightly wrong
/// drops the app into `.loadFailed`, which is a dead end.
///
/// Its only caller is behind `#if DEBUG`, so no shipped build has a route to it. Keep it
/// that way: this overwrites `state.json` wholesale, which on a real device is somebody's
/// history.
public enum DemoData {
    /// Weeks of history to generate. Nine months, so the yearly chart has something in it.
    static let weeks = 38
    /// The max test climbs from here to `finalMax` across those weeks.
    static let startMax = 24
    static let finalMax = 52
    /// Days at the end that are never missed.
    ///
    /// The streak is the number on the Train tab and the thing the listing promises, so a
    /// screenshot that lands on a missed Wednesday sells nothing. Older history still has
    /// gaps in it, which is what makes it look like a person's.
    static let cleanTailDays = 24

    /// A deterministic pseudo-random sequence. `Math.random` would make screenshots
    /// irreproducible, and a seeded generator keeps the same history every run.
    private struct Rolls {
        private var value: UInt64
        init(seed: UInt64) { value = seed }
        /// xorshift64. Good enough to make a history look human, and stable across runs.
        mutating func next() -> UInt64 {
            value ^= value << 13
            value ^= value >> 7
            value ^= value << 17
            return value
        }
        mutating func chance(_ percent: Int) -> Bool { Int(next() % 100) < percent }
        mutating func inRange(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
    }

    public static func state(
        today: Date = Date(),
        calendar: Calendar = .current,
        // Every day, matching what a real new user now gets. While this was Mon/Wed/Fri
        // the demo state described a plan the app no longer creates, and the Train tab's
        // seven-day chart screenshotted with three bars and four gaps — which also made
        // the week-over-week trend swing on whether a window happened to catch three
        // sessions or four, rather than on progression.
        trainingWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    ) -> PersistedState {
        var rolls = Rolls(seed: 0x5EED_5EED)
        var workouts: [Workout] = []
        var maxTests: [MaxTest] = []

        let todayKey = DayKey.make(today, calendar: calendar)
        let firstKey = DayKey.adding(-(weeks * 7), to: todayKey, calendar: calendar) ?? todayKey
        let days = DayKey.range(from: firstKey, through: todayKey, calendar: calendar)
        guard !days.isEmpty else { return PersistedState() }

        var sessionsDone = 0

        for (index, dayKey) in days.enumerated() {
            guard let date = DayKey.date(dayKey, calendar: calendar) else { continue }
            let progress = Double(index) / Double(max(1, days.count - 1))
            let currentMax = startMax + Int((Double(finalMax - startMax) * progress).rounded())
            let isTrainingDay = trainingWeekdays.contains(calendar.component(.weekday, from: date))

            // A max test at the start and then every ten weeks, which is what finishing a
            // block prompts for.
            if index % 70 == 0 {
                maxTests.append(MaxTest(reps: currentMax, takenAt: at(date, hour: 8, calendar: calendar),
                                        dayKey: dayKey))
            }

            let isRecent = days.count - index <= cleanTailDays

            if isTrainingDay {
                // Real people miss about one session in eight. A history with no gaps in
                // it looks synthetic, and the streak rules exist precisely for the gaps.
                // The last few weeks are exempt so the live streak is always worth a
                // screenshot.
                guard isRecent || !rolls.chance(12) else { continue }

                let target = max(1, Int((Double(currentMax) * 0.60).rounded()))
                // Most sessions land exactly on target; a few fall a little short, which
                // is what the deload rule is there for.
                let completed = rolls.chance(80) ? target : max(1, target - rolls.inRange(1...5))
                let started = at(date, hour: rolls.inRange(6...20), calendar: calendar)

                workouts.append(Workout(
                    dayKey: dayKey,
                    startedAt: started,
                    sets: [CompletedSet(
                        target: target,
                        completed: completed,
                        startedAt: started,
                        duration: Double(completed) * Double(rolls.inRange(2...3)),
                        engine: .proximity
                    )],
                    planID: PlanCatalog.adaptiveID,
                    sessionIndex: sessionsDone
                ))
                sessionsDone += 1
            } else if rolls.chance(14) {
                // A free set at a desk on an off day. Counts toward the day, never toward
                // the plan.
                let started = at(date, hour: rolls.inRange(9...21), calendar: calendar)
                let reps = rolls.inRange(10...25)
                workouts.append(Workout(
                    dayKey: dayKey,
                    startedAt: started,
                    sets: [CompletedSet(target: 0, completed: reps, startedAt: started,
                                        duration: Double(reps) * 2.4, engine: .proximity)]
                ))
            }
        }

        var state = PersistedState()
        state.workouts = workouts
        state.maxTests = maxTests
        state.hasCompletedOnboarding = true
        state.settings = Preferences(engine: .proximity, voice: .everyRep, syncToHealth: false)
        state.plan = PlanState(
            planID: PlanCatalog.adaptiveID,
            baseMax: finalMax,
            sessionIndex: sessionsDone % 30,
            blockIndex: sessionsDone / 30,
            trainingWeekdays: trainingWeekdays,
            startedOn: firstKey
        )
        return state
    }

    private static func at(_ day: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}