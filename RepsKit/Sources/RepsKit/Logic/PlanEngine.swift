import Foundation

/// The plans a user can pick. Data, not code — adding a plan is adding a row here plus,
/// for a `.table` plan, its table in `PlanTables`.
public enum PlanCatalog {
    public static let adaptiveID = "adaptive"
    public static let dailyGoalID = "daily-goal"

    public static let all: [PlanTemplate] = [
        PlanTemplate(
            id: adaptiveID,
            name: "Adaptive",
            summary: "Five sets built from your max. Steps up when you finish, backs off when you don't.",
            kind: .adaptive,
            sessionsPerBlock: 30,
            sessionsPerWeek: 3,
            isPro: true
        ),
        PlanTemplate(
            id: "hundred",
            name: "100 Push-Ups",
            summary: "The classic six-week table. Same sets for everyone, no scaling.",
            kind: .table,
            sessionsPerBlock: 18,
            sessionsPerWeek: 3,
            isPro: true
        ),
        PlanTemplate(
            id: "pyramid",
            name: "Prison Ladder",
            summary: "Up to the top rung and back down. One rung higher every session.",
            kind: .pyramid,
            sessionsPerBlock: 24,
            sessionsPerWeek: 4,
            isPro: true
        ),
        PlanTemplate(
            id: dailyGoalID,
            name: "Daily Goal",
            summary: "One number a day, split however you like. No prescribed sets.",
            kind: .dailyGoal,
            sessionsPerBlock: 0,
            sessionsPerWeek: 7,
            isPro: false
        )
    ]

    public static func template(_ id: String) -> PlanTemplate? {
        all.first { $0.id == id }
    }

    /// Falls back to the free plan rather than trapping. A state referencing a plan that
    /// no longer ships must still open.
    public static func templateOrDefault(_ id: String) -> PlanTemplate {
        template(id) ?? all.first { $0.id == dailyGoalID }!
    }
}

enum PlanTables {
    /// hundredpushups.com, middle column (initial test 11–20 reps), six weeks of three
    /// sessions. Reproduced as published: a named program that quietly rescales itself is
    /// not the program the user chose.
    static let hundred: [[Int]] = [
        [10, 12, 7, 7, 9],       [10, 12, 8, 8, 12],      [11, 15, 9, 9, 13],
        [14, 14, 10, 10, 15],    [14, 16, 12, 12, 17],    [16, 17, 14, 14, 20],
        [12, 17, 13, 13, 17],    [14, 19, 14, 14, 19],    [16, 21, 15, 15, 21],
        [18, 22, 16, 16, 25],    [20, 25, 20, 20, 28],    [23, 28, 23, 23, 33],
        [28, 35, 25, 22, 35],    [30, 38, 26, 24, 38],    [32, 40, 30, 26, 40],
        [36, 40, 30, 24, 40],    [38, 42, 32, 26, 42],    [40, 45, 35, 30, 45]
    ]
}

/// Everything a plan does, as pure functions over `PlanState`.
///
/// Nothing here reads or writes storage and nothing is cached. The schedule shown on the
/// Plan tab is recomputed on every render, which is why it can never be stale.
public enum PlanEngine {
    /// The adaptive prescription's shape: one near-max opening set, then four back-off
    /// sets. Sums to roughly twice the user's max, which is the volume the published
    /// six-week programs converge on.
    static let adaptiveRatios: [Double] = [0.80, 0.30, 0.28, 0.30, 0.30]

    /// How many sessions at one level before the load steps up.
    static let sessionsPerLevel = 3
    /// Volume added per level. Ten levels across a 30-session block lands at +45%.
    static let levelIncrement = 0.05
    /// How far a deload backs the anchor off. Two failed sessions means the anchor was
    /// wrong, not that the user was lazy.
    static let deloadFactor = 0.85

    // MARK: - Prescription

    /// The sets for a given session index within the current block.
    ///
    /// `sessionIndex` is passed explicitly rather than read off `state` so the Plan tab can
    /// render the next several sessions without mutating anything.
    public static func sets(for state: PlanState, sessionIndex: Int) -> [Int] {
        let template = PlanCatalog.templateOrDefault(state.planID)
        switch template.kind {
        case .adaptive:
            let level = max(0, sessionIndex) / sessionsPerLevel
            let scale = 1 + Double(level) * levelIncrement
            return adaptiveRatios.map { ratio in
                max(1, Int((Double(state.baseMax) * ratio * scale).rounded()))
            }

        case .table:
            let table = PlanTables.hundred
            guard !table.isEmpty else { return [] }
            // Past the end of the table the last session repeats rather than the plan
            // silently ending with an empty prescription.
            return table[min(max(0, sessionIndex), table.count - 1)]

        case .pyramid:
            // Top rung is calibrated so the first session totals about the user's max,
            // then climbs one rung per session.
            let base = max(2, Int((Double(state.baseMax) * 0.35).rounded()))
            let top = base + max(0, sessionIndex)
            return Array(1...top) + Array((1..<top).reversed())

        case .dailyGoal:
            return []
        }
    }

    /// Total reps prescribed for a session.
    public static func total(for state: PlanState, sessionIndex: Int) -> Int {
        let template = PlanCatalog.templateOrDefault(state.planID)
        if template.kind == .dailyGoal { return state.dailyGoal }
        return sets(for: state, sessionIndex: sessionIndex).reduce(0, +)
    }

    // MARK: - Progression

    /// Fold a finished session into the plan.
    ///
    /// Completing every prescribed rep advances one session and clears the failure count.
    /// Falling short repeats the same session. Two consecutive failures deload the anchor
    /// and advance anyway, because repeating a session the user cannot do is a dead end.
    ///
    /// Idempotency note: this is *not* idempotent by itself, which is why the mutation
    /// stored is `.setPlan(newState)` — a whole replacement state — and never a "advance
    /// by one" instruction.
    public static func advance(_ state: PlanState, with workout: Workout) -> PlanState {
        var next = state
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard template.kind != .dailyGoal else { return next }

        if workout.isComplete {
            next.consecutiveFailures = 0
            next.sessionIndex += 1
        } else {
            next.consecutiveFailures += 1
            if next.consecutiveFailures >= 2 {
                next.consecutiveFailures = 0
                next.baseMax = max(1, Int((Double(state.baseMax) * deloadFactor).rounded()))
                next.sessionIndex += 1
            }
        }

        // Block finished: bank it and park the index at zero. The UI reads
        // `needsMaxTest` off this and prompts for a fresh test before the next block.
        if template.sessionsPerBlock > 0, next.sessionIndex >= template.sessionsPerBlock {
            next.sessionIndex = 0
            next.blockIndex += 1
            next.startedOn = workout.dayKey
        }
        return next
    }

    /// A new block is starting and the anchor is stale. True only for plans that use one.
    public static func needsMaxTest(_ state: PlanState) -> Bool {
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard template.kind == .adaptive || template.kind == .pyramid else { return false }
        return state.sessionIndex == 0 && state.blockIndex > 0
    }

    // MARK: - Scheduling

    /// The next `count` sessions on or after `from`, skipping non-training weekdays and
    /// any day the user marked as rest.
    ///
    /// Days already trained are skipped too, so the schedule shown on the Plan tab always
    /// starts with work that still needs doing.
    public static func schedule(
        for state: PlanState,
        from: Date,
        count: Int,
        restDays: Set<String> = [],
        trainedDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [ScheduledSession] {
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard count > 0, template.kind != .dailyGoal, !state.trainingWeekdays.isEmpty else { return [] }

        var result: [ScheduledSession] = []
        var cursor = calendar.startOfDay(for: from)
        var index = state.sessionIndex
        // 120 days is four months of lookahead; past that a schedule is fiction anyway.
        var guardRail = 0

        while result.count < count, guardRail < 120 {
            guardRail += 1
            defer { cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor }

            let key = DayKey.make(cursor, calendar: calendar)
            let weekday = calendar.component(.weekday, from: cursor)
            guard state.trainingWeekdays.contains(weekday),
                  !restDays.contains(key),
                  !trainedDays.contains(key) else { continue }

            result.append(ScheduledSession(
                dayKey: key,
                date: cursor,
                sets: sets(for: state, sessionIndex: index),
                sessionIndex: index
            ))
            index += 1
        }
        return result
    }

    public static func next(
        for state: PlanState,
        from: Date,
        restDays: Set<String> = [],
        trainedDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> ScheduledSession? {
        schedule(
            for: state, from: from, count: 1,
            restDays: restDays, trainedDays: trainedDays, calendar: calendar
        ).first
    }

    /// Is `date` a training day for this plan? A `.dailyGoal` plan trains every day.
    public static func isTrainingDay(
        _ state: PlanState,
        date: Date,
        restDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Bool {
        let key = DayKey.make(date, calendar: calendar)
        guard !restDays.contains(key) else { return false }
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard template.kind != .dailyGoal else { return true }
        return state.trainingWeekdays.contains(calendar.component(.weekday, from: date))
    }
}
