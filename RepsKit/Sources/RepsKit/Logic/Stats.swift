import Foundation

public struct Records: Hashable, Sendable {
    /// Most reps in one unbroken set.
    public var bestSet: Int
    public var bestSetDayKey: String?
    /// Most reps in one calendar day.
    public var bestDay: Int
    public var bestDayKey: String?
    public var totalReps: Int
    public var totalSessions: Int
    public var longestStreak: Int

    public static let empty = Records(
        bestSet: 0, bestSetDayKey: nil, bestDay: 0, bestDayKey: nil,
        totalReps: 0, totalSessions: 0, longestStreak: 0
    )
}

public struct DayPoint: Hashable, Sendable, Identifiable {
    public var dayKey: String
    public var reps: Int
    public var goal: Int
    public var isRest: Bool

    public var id: String { dayKey }

    public init(dayKey: String, reps: Int, goal: Int, isRest: Bool) {
        self.dayKey = dayKey
        self.reps = reps
        self.goal = goal
        self.isRest = isRest
    }

    public var hitGoal: Bool { goal > 0 && reps >= goal }
    public var fraction: Double {
        guard goal > 0 else { return reps > 0 ? 1 : 0 }
        return min(1, Double(reps) / Double(goal))
    }
}

public enum Stats {
    /// Reps per day key. Days with no workout are absent, not zero — callers that need a
    /// dense series build it from a `DayKey.range`, which keeps the sparse map cheap.
    public static func repsByDay(_ workouts: [Workout]) -> [String: Int] {
        workouts.reduce(into: [:]) { acc, workout in
            acc[workout.dayKey, default: 0] += workout.totalReps
        }
    }

    public static func total(_ workouts: [Workout], from start: String, through end: String) -> Int {
        workouts.reduce(0) { $0 + (($1.dayKey >= start && $1.dayKey <= end) ? $1.totalReps : 0) }
    }

    /// A dense day-by-day series for a calendar range, suitable for a month grid or a bar
    /// chart. Rest days carry their reps (a rest day you trained on anyway still counts)
    /// but are flagged so the UI can draw them differently.
    public static func series(
        _ workouts: [Workout],
        from start: String,
        through end: String,
        goal: (String) -> Int,
        restDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [DayPoint] {
        let byDay = repsByDay(workouts)
        return DayKey.range(from: start, through: end, calendar: calendar).map { key in
            DayPoint(
                dayKey: key,
                reps: byDay[key] ?? 0,
                goal: goal(key),
                isRest: restDays.contains(key)
            )
        }
    }

    /// Consecutive days ending today on which the user trained.
    ///
    /// Two rules make this survivable rather than punishing. A **rest day the plan itself
    /// prescribed does not break the streak** — it is not a missed day, it is the plan
    /// working. And **today does not break it until it is over**: a streak is measured
    /// back from the most recent day that could still have been trained, so opening the
    /// app at 9am does not show a zero it will not deserve until midnight.
    public static func streak(
        trainedDays: Set<String>,
        restDays: Set<String>,
        today: String,
        calendar: Calendar = .current
    ) -> Int {
        var count = 0
        var cursor: String? = trainedDays.contains(today)
            ? today
            : DayKey.adding(-1, to: today, calendar: calendar)

        while let key = cursor, count < 3700 {
            if trainedDays.contains(key) {
                count += 1
            } else if restDays.contains(key) {
                // Passes through without incrementing: a rest day neither builds nor
                // breaks a streak.
            } else {
                break
            }
            cursor = DayKey.adding(-1, to: key, calendar: calendar)
        }
        return count
    }

    /// Longest streak ever, using the same rest-day rule as `streak`.
    public static func longestStreak(
        trainedDays: Set<String>,
        restDays: Set<String>,
        calendar: Calendar = .current
    ) -> Int {
        guard let first = trainedDays.min(), let last = trainedDays.max() else { return 0 }
        var best = 0
        var run = 0
        for key in DayKey.range(from: first, through: last, calendar: calendar) {
            if trainedDays.contains(key) {
                run += 1
                best = max(best, run)
            } else if restDays.contains(key) {
                continue
            } else {
                run = 0
            }
        }
        return best
    }

    public static func records(
        _ workouts: [Workout],
        restDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Records {
        guard !workouts.isEmpty else { return .empty }

        // Ties break toward the *earlier* day in both records, so a personal best does not
        // appear to move every time it is equalled.
        let bestSet = workouts
            .filter { $0.bestSet > 0 }
            .sorted { $0.bestSet == $1.bestSet ? $0.dayKey < $1.dayKey : $0.bestSet > $1.bestSet }
            .first

        let byDay = repsByDay(workouts)
        let bestDay = byDay
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .first

        let trained = Set(byDay.filter { $0.value > 0 }.keys)
        return Records(
            bestSet: bestSet?.bestSet ?? 0,
            bestSetDayKey: bestSet?.dayKey,
            bestDay: bestDay?.value ?? 0,
            bestDayKey: bestDay?.key,
            totalReps: workouts.reduce(0) { $0 + $1.totalReps },
            totalSessions: workouts.count,
            longestStreak: longestStreak(trainedDays: trained, restDays: restDays, calendar: calendar)
        )
    }

    /// Mean reps per day across days that were *available* to train — rest days are
    /// excluded from the denominator as well as the numerator, which is the whole reason
    /// rest days are stored at all.
    public static func average(
        _ workouts: [Workout],
        from start: String,
        through end: String,
        restDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Int {
        let days = DayKey.range(from: start, through: end, calendar: calendar)
            .filter { !restDays.contains($0) }
        guard !days.isEmpty else { return 0 }
        return Int((Double(total(workouts, from: start, through: end)) / Double(days.count)).rounded())
    }
}
