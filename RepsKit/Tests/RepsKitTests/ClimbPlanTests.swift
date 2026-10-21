import Testing
import Foundation
@testable import RepsKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private let start = "2026-09-01"

private func climb(
    goal: Int = 40,
    step: Int = PlanState.defaultClimbStep,
    ceiling: Int = PlanState.defaultClimbCeiling,
    startedOn: String = start
) -> PlanState {
    PlanState(
        planID: PlanCatalog.climbID,
        baseMax: 40,
        startedOn: startedOn,
        dailyGoal: goal,
        climbStep: step,
        climbCeiling: ceiling
    )
}

/// `climbGoal` is asked about the day *after* the history it is given, so these helpers
/// build a run of days starting at `start` and then ask about the next one.
private func days(_ reps: [Int], from first: String = start) -> [String: Int] {
    var out: [String: Int] = [:]
    var key = first
    for value in reps {
        out[key] = value
        key = DayKey.adding(1, to: key, calendar: utc) ?? key
    }
    return out
}

private func dayAfter(_ count: Int, from first: String = start) -> String {
    DayKey.adding(count, to: first, calendar: utc) ?? first
}

private func goal(after reps: [Int], plan: PlanState = climb()) -> Int {
    PlanEngine.climbGoal(
        for: plan,
        on: dayAfter(reps.count),
        repsByDay: days(reps),
        calendar: utc
    )
}

@Suite("Climb plan")
struct ClimbPlanTests {

    @Test("Day one is the number you set")
    func startsWhereYouPutIt() {
        let plan = climb(goal: 40)
        #expect(PlanEngine.climbGoal(for: plan, on: start, repsByDay: [:], calendar: utc) == 40)
    }

    @Test("Hitting the goal steps it up, every day")
    func hittingClimbs() {
        // 40 hit -> 42 hit -> 44 hit -> 46.
        #expect(goal(after: [40]) == 42)
        #expect(goal(after: [40, 42]) == 44)
        #expect(goal(after: [40, 42, 44]) == 46)
    }

    @Test("Overshooting counts as hitting, and does not step twice")
    func overshootStepsOnce() {
        // The whole point of letting a finished set run on: doing 60 when the goal was 40
        // is one good day, not ten days of progress banked at once.
        #expect(goal(after: [60]) == 42)
    }

    @Test("One short day holds the number")
    func oneMissHolds() {
        // Everybody has one bad day, and a plan that punishes it is a plan people quit.
        #expect(goal(after: [39]) == 40)
        #expect(goal(after: [40, 41]) == 42)
    }

    @Test("Two short days in a row back it off 15%")
    func twoMissesDeload() {
        // Same deload the adaptive plan uses. 40 -> 34.
        #expect(goal(after: [39, 20]) == 34)
    }

    @Test("A hit between two misses resets the count")
    func missesMustBeConsecutive() {
        // short, hit, short is not two in a row, so nothing deloads.
        // 40 short -> 40; hit 40 -> 42; short -> 42.
        #expect(goal(after: [39, 40, 10]) == 42)
    }

    @Test("A day you did not train is neither a hit nor a miss")
    func untrainedDaysDoNotMove() {
        // The rule that makes a holiday survivable. Seven days away would otherwise be
        // three consecutive deloads and a goal 40% lower than the one you left.
        #expect(goal(after: [40, 0, 0, 0, 0, 0, 0]) == 42)
        // And the same judgement the streak makes: an absent day is absent, not a zero.
        var sparse = days([40])
        sparse[dayAfter(3)] = 42
        let result = PlanEngine.climbGoal(
            for: climb(), on: dayAfter(4), repsByDay: sparse, calendar: utc
        )
        #expect(result == 44)
    }

    @Test("The climb stops at the ceiling and holds there")
    func ceilingHolds() {
        let plan = climb(goal: 46, ceiling: 50)
        #expect(goal(after: [46], plan: plan) == 48)
        #expect(goal(after: [46, 48], plan: plan) == 50)
        // Arriving is the win condition, not the end of the plan: it holds, it does not
        // keep climbing and it does not reset.
        #expect(goal(after: [46, 48, 50], plan: plan) == 50)
        #expect(goal(after: [46, 48, 50, 50, 50], plan: plan) == 50)
    }

    @Test("A goal above the ceiling is clamped rather than honoured")
    func startAboveCeilingClamps() {
        let plan = climb(goal: 200, ceiling: 50)
        #expect(PlanEngine.climbGoal(for: plan, on: start, repsByDay: [:], calendar: utc) == 50)
    }

    @Test("Today's goal never depends on today")
    func todayIsNotScoredYet() {
        // Opening the app mid-session must not move the number under the user.
        let today = dayAfter(1)
        let before = PlanEngine.climbGoal(for: climb(), on: today, repsByDay: days([40]), calendar: utc)
        var withToday = days([40])
        withToday[today] = 42
        let after = PlanEngine.climbGoal(for: climb(), on: today, repsByDay: withToday, calendar: utc)
        #expect(before == after)
    }

    @Test("Reading the goal twice gives the same answer")
    func derivationIsStable() {
        // The reason the climb derives instead of mutating: progression that writes state
        // has to fire exactly once a day, and the spool re-applies envelopes after a
        // crash. Nothing here can double-step because nothing here is stored.
        let history = days([40, 42, 30, 44, 46])
        let a = PlanEngine.climbGoal(for: climb(), on: dayAfter(5), repsByDay: history, calendar: utc)
        let b = PlanEngine.climbGoal(for: climb(), on: dayAfter(5), repsByDay: history, calendar: utc)
        #expect(a == b)
    }

    @Test("The one-pass range derivation agrees with the per-day one, day for day")
    func rangeMatchesPerDay() {
        // Two derivations of the same number that can disagree is worse than one slow
        // one, so the fast path the charts use is pinned against the simple one.
        let history = days([40, 42, 30, 0, 44, 20, 20, 46, 48])
        let plan = climb()
        let from = start
        let through = dayAfter(12)

        let bulk = PlanEngine.climbGoals(
            for: plan, from: from, through: through, repsByDay: history, calendar: utc
        )
        for key in DayKey.range(from: from, through: through, calendar: utc) {
            let single = PlanEngine.climbGoal(
                for: plan, on: key, repsByDay: history, calendar: utc
            )
            #expect(bulk[key] == single, "disagreement on \(key)")
        }
    }

    @Test("A range starting before the plan did still reports the starting goal")
    func rangeBeforeStart() {
        // The month grid asks about the whole calendar month, including days before the
        // user ever opened the app. Those must read as the starting number, not as a gap.
        let plan = climb(startedOn: dayAfter(5))
        let goals = PlanEngine.climbGoals(
            for: plan, from: start, through: dayAfter(7),
            repsByDay: [:], calendar: utc
        )
        #expect(goals[start] == 40)
        #expect(goals[dayAfter(7)] == 40)
        #expect(goals.count == 8)
    }

    @Test("Finishing a climb session never mutates the plan")
    func advanceIsANoOp() {
        let plan = climb()
        let session = Workout(
            dayKey: start,
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            sets: [CompletedSet(target: 40, completed: 40,
                                startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .depth)],
            planID: PlanCatalog.climbID,
            sessionIndex: 0
        )
        #expect(PlanEngine.advance(plan, with: session) == plan)
    }

    @Test("A climb prescribes no sets, no rest days and every day")
    func shapeMatchesDailyGoal() {
        let plan = climb()
        #expect(PlanEngine.sets(for: plan, sessionIndex: 0).isEmpty)
        #expect(PlanEngine.schedule(for: plan, from: Date(), count: 5, calendar: utc).isEmpty)
        #expect(PlanEngine.prescribedRestDays(for: plan, from: start, through: dayAfter(30),
                                              calendar: utc).isEmpty)
        #expect(PlanEngine.isTrainingDay(plan, date: DayKey.date(start, calendar: utc)!,
                                         calendar: utc))
        #expect(PlanEngine.needsMaxTest(plan) == false)
        #expect(PlanCatalog.isDailyNumber(PlanCatalog.climbID))
    }

    @Test("Step and ceiling are clamped on the way in and the way out")
    func boundsAreEnforced() {
        var plan = climb(step: 99, ceiling: 1)
        #expect(plan.climbStep == PlanState.maxClimbStep)
        #expect(plan.climbCeiling == PlanState.minClimbCeiling)
        plan.climbStep = 0
        plan.climbCeiling = 99_999
        #expect(plan.climbStep == 1)
        #expect(plan.climbCeiling == PlanState.maxClimbCeiling)
    }

    @Test("A plan written before the climb existed still decodes")
    func optionalForever() throws {
        // The invariant that keeps `state.json` openable: new fields are optional, and a
        // file without them must not drop the app into `.loadFailed`.
        let legacy = """
        {"planID":"climb","baseMax":40,"sessionIndex":0,"blockIndex":0,
         "consecutiveFailures":0,"trainingWeekdays":[1,2,3,4,5,6,7],
         "startedOn":"2026-09-01","dailyGoal":40}
        """
        let decoded = try JSONDecoder().decode(PlanState.self, from: Data(legacy.utf8))
        #expect(decoded.climbStep == PlanState.defaultClimbStep)
        #expect(decoded.climbCeiling == PlanState.defaultClimbCeiling)
    }

    @Test("The climb is in the catalog and trains every day")
    func climbIsOffered() {
        let template = PlanCatalog.template(PlanCatalog.climbID)
        #expect(template?.kind == .climb)
        #expect(template?.sessionsPerWeek == 7)
    }
}
