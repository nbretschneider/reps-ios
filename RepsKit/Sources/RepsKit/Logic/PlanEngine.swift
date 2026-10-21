import Foundation

/// The plans a user can pick. Data, not code — adding a plan is adding a row here plus,
/// for a `.table` plan, its table in `PlanTables`.
public enum PlanCatalog {
    public static let adaptiveID = "adaptive"
    public static let dailyGoalID = "daily-goal"
    public static let climbID = "climb"

    /// The two plans that are one number a day rather than a prescribed session. The goal
    /// editor offers these as a toggle, so it needs to know which is which without
    /// hardcoding ids at the call site.
    public static func isDailyNumber(_ id: String) -> Bool {
        let kind = templateOrDefault(id).kind
        return kind.isDailyNumber
    }

    public static let all: [PlanTemplate] = [
        PlanTemplate(
            id: adaptiveID,
            name: "Adaptive",
            summary: "Built from your max. Steps up when you finish, backs off when you don't.",
            kind: .adaptive,
            sessionsPerBlock: 30,
            sessionsPerWeek: 3
        ),
        PlanTemplate(
            id: "hundred",
            name: "100 Push-Ups",
            summary: "The classic six-week table. Same sets for everyone, no scaling.",
            kind: .table,
            sessionsPerBlock: 18,
            sessionsPerWeek: 3
        ),
        PlanTemplate(
            id: "pyramid",
            name: "Prison Ladder",
            summary: "Up to the top rung and back down. One rung higher every session.",
            kind: .pyramid,
            sessionsPerBlock: 24,
            sessionsPerWeek: 4
        ),
        PlanTemplate(
            id: dailyGoalID,
            name: "Daily Goal",
            summary: "One number a day, split however you like. No prescribed sets.",
            kind: .dailyGoal,
            sessionsPerBlock: 0,
            sessionsPerWeek: 7
        ),
        PlanTemplate(
            id: climbID,
            name: "Climb",
            summary: "Start where you are. Every day you hit the number, tomorrow goes up.",
            kind: .climb,
            sessionsPerBlock: 0,
            sessionsPerWeek: 7
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
    /// The adaptive prescription, as fractions of the user's max, keyed by how many sets
    /// the session is split into.
    ///
    /// **One set is the default**, and it is not a token version of the real thing: 0.60 of
    /// max is a genuine working set, repeatable three times a week, and the +5%-per-level
    /// progression carries it to 0.87 of max by the end of a 30-session block. Finishing a
    /// block doing nearly your old max in one unbroken set is exactly the right moment to
    /// re-test, which is what the block boundary already prompts for.
    ///
    /// The five-set row is the original ladder, unchanged, so turning this all the way up
    /// gives back exactly what the plan used to prescribe.
    static let adaptiveRatios: [Int: [Double]] = [
        1: [0.60],
        2: [0.75, 0.35],
        3: [0.80, 0.32, 0.30],
        4: [0.80, 0.30, 0.28, 0.30],
        5: [0.80, 0.30, 0.28, 0.30, 0.30]
    ]

    /// What "Multiple sets" turns on. Three is enough to feel like a session and short
    /// enough to finish.
    public static let defaultMultiSetCount = 3

    /// Does this plan's prescription respond to `PlanState.setCount`?
    ///
    /// Only the adaptive one does. A `.table` plan reproduces a published program literally
    /// and a `.pyramid` *is* its shape, so reshaping either would make it a different
    /// program wearing the same name. The UI reads this to hide the control rather than
    /// offer one that does nothing.
    public static func honoursSetCount(_ state: PlanState) -> Bool {
        PlanCatalog.templateOrDefault(state.planID).kind == .adaptive
    }

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
            // `setCount` is clamped by its accessor, so the lookup cannot miss. The
            // fallback is the single set rather than a crash or an empty session.
            let ratios = adaptiveRatios[state.setCount] ?? adaptiveRatios[1]!
            return ratios.map { ratio in
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

        case .dailyGoal, .climb:
            return []
        }
    }

    /// Total reps prescribed for a session.
    ///
    /// For `.climb` this is the number the climb *started* at, not today's goal: today's
    /// depends on the whole history and comes from `climbGoal(for:on:repsByDay:)`. Nothing
    /// in the app reads this for a climb plan — `RepsStore.goalToday` is the single
    /// resolution point — and a caller that needs a live number should go there.
    public static func total(for state: PlanState, sessionIndex: Int) -> Int {
        let template = PlanCatalog.templateOrDefault(state.planID)
        if template.kind.isDailyNumber { return state.dailyGoal }
        return sets(for: state, sessionIndex: sessionIndex).reduce(0, +)
    }

    // MARK: - Climb

    /// How far back the climb is reconstructed. Two years of daily stepping saturates at
    /// any sane ceiling long before this, so the bound costs nothing and stops a corrupt
    /// `startedOn` from walking the calendar forever.
    static let climbLookbackDays = 730

    /// Today's goal for a `.climb` plan, derived from scratch every time it is read.
    ///
    /// Nothing about the climb is stored except where it began, how big a step is, and
    /// where it stops. The current goal is a pure function of those three and the days
    /// since — which is the same reason the Plan tab's schedule is recomputed on every
    /// render: a derived number cannot go stale, and it cannot double-count.
    ///
    /// That last part is the real reason it works this way. Progression that mutates state
    /// has to fire exactly once per day, and the persistence design re-applies envelopes
    /// after a crash. A plan that stepped on every `advance` would step twice for two
    /// sessions in one day, and again on a replay. Deriving sidesteps the whole class of
    /// bug: `advance` does nothing at all for a climb, so there is nothing to replay.
    ///
    /// The rules, in order:
    ///
    /// - **A day you did not train does not move the goal.** Not a hit, not a miss. This is
    ///   the same judgement the streak makes about rest days, and without it a week away
    ///   compounds three deloads and hands back a goal 40% lower than it should be.
    /// - **Reaching the goal steps up** by `climbStep`, never past `climbCeiling`.
    /// - **Falling short holds.** One short day changes nothing: everybody has one.
    /// - **Two short days in a row back the goal off 15%** and reset the count, which is the
    ///   same deload the adaptive plan uses, for the same reason — repeating a number you
    ///   cannot reach is a dead end.
    public static func climbGoal(
        for state: PlanState,
        on dayKey: String,
        repsByDay: [String: Int],
        calendar: Calendar = .current
    ) -> Int {
        let ceiling = state.climbCeiling
        var goal = min(max(1, state.dailyGoal), ceiling)

        // The climb is evaluated on the days *before* the one being asked about: today's
        // goal cannot depend on whether today has been finished yet.
        guard let lastScored = DayKey.adding(-1, to: dayKey, calendar: calendar),
              lastScored >= state.startedOn else { return goal }

        let earliest = DayKey.adding(-climbLookbackDays, to: dayKey, calendar: calendar)
        let start = max(state.startedOn, earliest ?? state.startedOn)
        guard start <= lastScored else { return goal }

        var shortDays = 0
        for key in DayKey.range(from: start, through: lastScored, calendar: calendar) {
            score(key, goal: &goal, shortDays: &shortDays, state: state,
                  ceiling: ceiling, repsByDay: repsByDay)
        }
        return goal
    }

    /// Every day's goal across a range, in one walk.
    ///
    /// `climbGoal` re-derives from the start of the plan on every call, which is the right
    /// shape for one day and quadratic for a chart. The month grid and the year chart ask
    /// about every day at once and recompute on every render, so they get a single pass.
    ///
    /// Agrees with `climbGoal` day for day, which is pinned by a test: two derivations of
    /// the same number that can disagree is worse than one slow one.
    public static func climbGoals(
        for state: PlanState,
        from start: String,
        through end: String,
        repsByDay: [String: Int],
        calendar: Calendar = .current
    ) -> [String: Int] {
        guard start <= end else { return [:] }
        let ceiling = state.climbCeiling
        var goal = min(max(1, state.dailyGoal), ceiling)

        let earliest = DayKey.adding(-climbLookbackDays, to: end, calendar: calendar)
        let walkStart = max(state.startedOn, earliest ?? state.startedOn)

        var out: [String: Int] = [:]
        var shortDays = 0
        for key in DayKey.range(from: min(walkStart, start), through: end, calendar: calendar) {
            // Recorded *before* the day is scored: a day's goal cannot depend on whether
            // that day has been finished yet, which is the same rule `climbGoal` follows
            // by scoring only up to the day before.
            if key >= start { out[key] = goal }
            guard key >= walkStart else { continue }
            score(key, goal: &goal, shortDays: &shortDays, state: state,
                  ceiling: ceiling, repsByDay: repsByDay)
        }
        return out
    }

    /// One day's effect on a running climb. Shared so the two derivations above cannot
    /// drift apart.
    private static func score(
        _ key: String,
        goal: inout Int,
        shortDays: inout Int,
        state: PlanState,
        ceiling: Int,
        repsByDay: [String: Int]
    ) {
        let reps = repsByDay[key] ?? 0
        guard reps > 0 else { return }

        if reps >= goal {
            goal = min(ceiling, goal + state.climbStep)
            shortDays = 0
        } else {
            shortDays += 1
            if shortDays >= 2 {
                shortDays = 0
                goal = max(1, Int((Double(goal) * deloadFactor).rounded()))
            }
        }
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
        // Neither of the one-number-a-day plans has a session index to advance. A climb's
        // goal is derived from history by `climbGoal`, so there is deliberately nothing to
        // mutate here — see the note there about replay.
        guard !template.kind.isDailyNumber else { return next }

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
        guard count > 0, !template.kind.isDailyNumber, !state.trainingWeekdays.isEmpty else { return [] }

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

    /// Every day in the range the plan never asked anyone to train on.
    ///
    /// The streak rule is that **a rest day the plan prescribed does not break a streak**.
    /// Counting only the days a user explicitly marked would break a perfectly compliant
    /// three-days-a-week streak every single Tuesday, which is the opposite of the rule.
    ///
    /// A one-number-a-day plan asks for every day, so it prescribes no rest.
    public static func prescribedRestDays(
        for state: PlanState,
        from start: String,
        through end: String,
        calendar: Calendar = .current
    ) -> Set<String> {
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard !template.kind.isDailyNumber, !state.trainingWeekdays.isEmpty else { return [] }
        return Set(
            DayKey.range(from: start, through: end, calendar: calendar).filter { key in
                guard let weekday = DayKey.weekday(key, calendar: calendar) else { return false }
                return !state.trainingWeekdays.contains(weekday)
            }
        )
    }

    /// Is `date` a training day? A one-number-a-day plan trains every day.
    public static func isTrainingDay(
        _ state: PlanState,
        date: Date,
        restDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> Bool {
        let key = DayKey.make(date, calendar: calendar)
        guard !restDays.contains(key) else { return false }
        let template = PlanCatalog.templateOrDefault(state.planID)
        guard !template.kind.isDailyNumber else { return true }
        return state.trainingWeekdays.contains(calendar.component(.weekday, from: date))
    }
}
