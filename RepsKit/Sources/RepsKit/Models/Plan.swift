import Foundation

/// How a plan decides what today's sets are. One generator per case, all of them pure
/// functions of `PlanState` in `PlanEngine` — nothing is materialized, so a schedule can
/// never drift out of sync with the state that produced it.
public enum PlanKind: String, Codable, Hashable, Sendable {
    /// Scaled off the user's measured max, stepping up as sessions complete and deloading
    /// after two failures. The default. How many sets it splits into is `setCount`, and
    /// that defaults to one.
    case adaptive
    /// A published table, reproduced literally. No scaling — the point of following a
    /// named program is following it.
    case table
    /// A pyramid: 1, 2, 3 ... n ... 3, 2, 1. `n` grows one rung per completed session.
    case pyramid
    /// No prescribed sets at all — one number to reach per day, split however you like.
    case dailyGoal
}

/// A plan the user can choose. Templates are data, not code: adding one is adding a row.
public struct PlanTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// One line, shown under the name in the picker.
    public var summary: String
    public var kind: PlanKind
    /// Sessions in one block. For `.dailyGoal` this is unused.
    public var sessionsPerBlock: Int
    /// How many days a week the plan trains, used only to describe it in the picker.
    public var sessionsPerWeek: Int
    public var isPro: Bool

    public init(
        id: String,
        name: String,
        summary: String,
        kind: PlanKind,
        sessionsPerBlock: Int,
        sessionsPerWeek: Int,
        isPro: Bool
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.kind = kind
        self.sessionsPerBlock = sessionsPerBlock
        self.sessionsPerWeek = sessionsPerWeek
        self.isPro = isPro
    }
}

/// Where the user currently is inside their chosen plan.
///
/// This is the only mutable plan data. Everything a session needs is derived from it by
/// `PlanEngine`, so a plan can be recomputed from scratch at any time and there is no
/// materialized schedule to fall out of sync with reality.
public struct PlanState: Codable, Hashable, Sendable {
    public var planID: String
    /// Best single set from the most recent max test. The anchor every adaptive
    /// prescription scales off.
    public var baseMax: Int
    /// Completed sessions inside the current block, `0..<sessionsPerBlock`.
    public var sessionIndex: Int
    /// Blocks finished. Shown as "Plan 3" and used to know when to re-test.
    public var blockIndex: Int
    /// Sessions failed back to back. Two triggers a deload; completing one resets it.
    public var consecutiveFailures: Int
    /// `Calendar` weekday numbers, 1 = Sunday ... 7 = Saturday.
    public var trainingWeekdays: Set<Int>
    /// Day key the current block started on.
    public var startedOn: String
    /// Only meaningful for `.dailyGoal`.
    public var dailyGoal: Int
    /// Backing store for `setCount`. Optional, forever: a `state.json` written before this
    /// field existed still has to decode, and an undecodable file is a dead end.
    private var setCountValue: Int?

    public init(
        planID: String,
        baseMax: Int,
        sessionIndex: Int = 0,
        blockIndex: Int = 0,
        consecutiveFailures: Int = 0,
        trainingWeekdays: Set<Int> = [2, 4, 6],   // Mon / Wed / Fri
        startedOn: String,
        dailyGoal: Int = 100,
        setCount: Int = PlanState.defaultSetCount
    ) {
        self.planID = planID
        self.baseMax = baseMax
        self.sessionIndex = sessionIndex
        self.blockIndex = blockIndex
        self.consecutiveFailures = consecutiveFailures
        self.trainingWeekdays = trainingWeekdays
        self.startedOn = startedOn
        self.dailyGoal = dailyGoal
        self.setCountValue = Self.clampSetCount(setCount)
    }

    /// One set. This is the product decision, not a placeholder.
    ///
    /// Five sets with rest between them is fifteen minutes. One set is two. Someone who has
    /// two minutes and is told to do fifteen does nothing at all, and a push-up app only
    /// works if it gets used on the days you do not feel like using it.
    public static let defaultSetCount = 1
    /// Past five the rest timers dominate and it stops being a thing anyone finishes.
    public static let maxSetCount = 5

    /// How many sets a session is split into, 1...5.
    ///
    /// Clamped on the way in *and* on the way out, so a hand-edited or future-written file
    /// carrying a nonsense value still produces a session someone can do.
    public var setCount: Int {
        get { Self.clampSetCount(setCountValue ?? Self.defaultSetCount) }
        set { setCountValue = Self.clampSetCount(newValue) }
    }

    /// True when the session is a single working set. The UI reads this to drop the set
    /// pips entirely — one pip next to the hero number reads as a stray chip.
    public var isSingleSet: Bool { setCount == 1 }

    private static func clampSetCount(_ value: Int) -> Int {
        min(maxSetCount, max(1, value))
    }
}

/// A session the plan says to do on a given day.
public struct ScheduledSession: Hashable, Sendable {
    public var dayKey: String
    public var date: Date
    public var sets: [Int]
    public var sessionIndex: Int

    public init(dayKey: String, date: Date, sets: [Int], sessionIndex: Int) {
        self.dayKey = dayKey
        self.date = date
        self.sets = sets
        self.sessionIndex = sessionIndex
    }

    public var total: Int { sets.reduce(0, +) }
}

/// A max test: as many push-ups as possible in one unbroken set. The number the whole
/// adaptive plan hangs off.
public struct MaxTest: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int
    public var takenAt: Date
    public var dayKey: String

    public init(id: UUID = UUID(), reps: Int, takenAt: Date, dayKey: String) {
        self.id = id
        self.reps = reps
        self.takenAt = takenAt
        self.dayKey = dayKey
    }
}
