import Testing
import Foundation
@testable import RepsKit

private func makeState(
    planID: String = PlanCatalog.adaptiveID,
    max: Int = 100,
    sessionIndex: Int = 0,
    blockIndex: Int = 0,
    failures: Int = 0,
    weekdays: Set<Int> = [2, 4, 6]
) -> PlanState {
    PlanState(
        planID: planID,
        baseMax: max,
        sessionIndex: sessionIndex,
        blockIndex: blockIndex,
        consecutiveFailures: failures,
        trainingWeekdays: weekdays,
        startedOn: "2026-08-03"
    )
}

private func workout(_ sets: [(target: Int, done: Int)], day: String = "2026-08-03") -> Workout {
    Workout(
        dayKey: day,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        sets: sets.map {
            CompletedSet(target: $0.target, completed: $0.done,
                         startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        },
        planID: PlanCatalog.adaptiveID,
        sessionIndex: 0
    )
}

@Suite("Adaptive prescription")
struct AdaptivePrescriptionTests {

    @Test("A 100-rep max prescribes the reference ladder")
    func referenceLadder() {
        // The shape the whole plan is built around: one near-max opening set, four
        // back-off sets, roughly twice the max in total.
        #expect(PlanEngine.sets(for: makeState(max: 100), sessionIndex: 0) == [80, 30, 28, 30, 30])
        #expect(PlanEngine.total(for: makeState(max: 100), sessionIndex: 0) == 198)
    }

    @Test("Load holds for three sessions, then steps up")
    func stepsUpEveryThirdSession() {
        let state = makeState(max: 100)
        let level0 = PlanEngine.sets(for: state, sessionIndex: 0)
        #expect(PlanEngine.sets(for: state, sessionIndex: 1) == level0)
        #expect(PlanEngine.sets(for: state, sessionIndex: 2) == level0)

        let level1 = PlanEngine.sets(for: state, sessionIndex: 3)
        #expect(level1 != level0)
        #expect(level1.reduce(0, +) > level0.reduce(0, +))
    }

    @Test("Volume climbs monotonically across a block")
    func volumeNeverGoesBackwards() {
        let state = makeState(max: 40)
        let totals = (0..<30).map { PlanEngine.total(for: state, sessionIndex: $0) }
        #expect(zip(totals, totals.dropFirst()).allSatisfy { $0 <= $1 })
        // Ten levels at +5% each.
        #expect(totals.last! > Int(Double(totals.first!) * 1.4))
    }

    @Test("A beginner never gets a zero-rep set")
    func neverPrescribesZero() {
        for max in 1...10 {
            let sets = PlanEngine.sets(for: makeState(max: max), sessionIndex: 0)
            #expect(sets.allSatisfy { $0 >= 1 })
        }
    }
}

@Suite("Progression")
struct ProgressionTests {

    @Test("Finishing every rep advances one session")
    func completionAdvances() {
        let state = makeState(max: 100)
        let next = PlanEngine.advance(state, with: workout([(80, 80), (30, 30), (28, 28), (30, 30), (30, 30)]))
        #expect(next.sessionIndex == 1)
        #expect(next.consecutiveFailures == 0)
        #expect(next.baseMax == 100)
    }

    @Test("Falling short repeats the same session")
    func failureRepeats() {
        let state = makeState(max: 100)
        let next = PlanEngine.advance(state, with: workout([(80, 62), (30, 30), (28, 28), (30, 30), (30, 30)]))
        #expect(next.sessionIndex == 0)
        #expect(next.consecutiveFailures == 1)
        #expect(next.baseMax == 100)
    }

    @Test("Two failures in a row deload the anchor and move on")
    func twoFailuresDeload() {
        var state = makeState(max: 100)
        let short = workout([(80, 40), (30, 30), (28, 28), (30, 30), (30, 30)])
        state = PlanEngine.advance(state, with: short)
        state = PlanEngine.advance(state, with: short)
        #expect(state.baseMax == 85)
        #expect(state.sessionIndex == 1)
        // Cleared, so the next failure starts a fresh count rather than deloading again.
        #expect(state.consecutiveFailures == 0)
    }

    @Test("A completion between two failures resets the failure count")
    func completionResetsFailures() {
        var state = makeState(max: 100)
        state = PlanEngine.advance(state, with: workout([(80, 10)]))
        #expect(state.consecutiveFailures == 1)
        state = PlanEngine.advance(state, with: workout([(80, 80)]))
        #expect(state.consecutiveFailures == 0)
        state = PlanEngine.advance(state, with: workout([(80, 10)]))
        #expect(state.baseMax == 100)   // not a deload — the failures were not consecutive
    }

    @Test("Deload never drives the anchor below one")
    func deloadHasAFloor() {
        var state = makeState(max: 1)
        let short = workout([(1, 0)])
        for _ in 0..<20 { state = PlanEngine.advance(state, with: short) }
        #expect(state.baseMax >= 1)
    }

    @Test("Finishing a block banks it and asks for a fresh max test")
    func blockRollover() {
        var state = makeState(max: 100, sessionIndex: 29)
        #expect(PlanEngine.needsMaxTest(state) == false)
        state = PlanEngine.advance(state, with: workout([(1, 1)], day: "2026-09-30"))
        #expect(state.sessionIndex == 0)
        #expect(state.blockIndex == 1)
        #expect(state.startedOn == "2026-09-30")
        #expect(PlanEngine.needsMaxTest(state))
    }

    @Test("A daily-goal plan has no progression to run")
    func dailyGoalDoesNotAdvance() {
        let state = makeState(planID: PlanCatalog.dailyGoalID, max: 100)
        let next = PlanEngine.advance(state, with: workout([(0, 50)]))
        #expect(next == state)
        #expect(PlanEngine.total(for: state, sessionIndex: 0) == state.dailyGoal)
        #expect(PlanEngine.sets(for: state, sessionIndex: 0).isEmpty)
    }
}

@Suite("Scheduling")
struct SchedulingTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-08-03 is a Monday.
    private var monday: Date { DayKey.date("2026-08-03", calendar: calendar)! }

    @Test("Only training weekdays are scheduled")
    func respectsTrainingWeekdays() {
        let state = makeState(weekdays: [2, 4, 6])   // Mon / Wed / Fri
        let schedule = PlanEngine.schedule(for: state, from: monday, count: 3, calendar: calendar)
        #expect(schedule.map(\.dayKey) == ["2026-08-03", "2026-08-05", "2026-08-07"])
    }

    @Test("Session indices advance across the schedule, so later sessions show heavier sets")
    func indicesAdvance() {
        let state = makeState(weekdays: [2, 4, 6])
        let schedule = PlanEngine.schedule(for: state, from: monday, count: 4, calendar: calendar)
        #expect(schedule.map(\.sessionIndex) == [0, 1, 2, 3])
        #expect(schedule.last!.total > schedule.first!.total)
    }

    @Test("Days the user marked as rest are skipped")
    func skipsRestDays() {
        let state = makeState(weekdays: [2, 4, 6])
        let schedule = PlanEngine.schedule(
            for: state, from: monday, count: 2, restDays: ["2026-08-05"], calendar: calendar
        )
        #expect(schedule.map(\.dayKey) == ["2026-08-03", "2026-08-07"])
    }

    @Test("A day already trained is not offered again")
    func skipsTrainedDays() {
        let state = makeState(weekdays: [2, 4, 6])
        let next = PlanEngine.next(
            for: state, from: monday, trainedDays: ["2026-08-03"], calendar: calendar
        )
        #expect(next?.dayKey == "2026-08-05")
    }

    @Test("A plan with no training weekdays schedules nothing rather than looping")
    func noWeekdaysIsEmpty() {
        let state = makeState(weekdays: [])
        #expect(PlanEngine.schedule(for: state, from: monday, count: 5, calendar: calendar).isEmpty)
    }

    @Test("Lookahead is bounded even when almost every day is a rest day")
    func lookaheadIsBounded() {
        let state = makeState(weekdays: [2])
        let allRest = Set(DayKey.range(from: "2026-08-01", through: "2027-08-01", calendar: calendar))
        let schedule = PlanEngine.schedule(
            for: state, from: monday, count: 5, restDays: allRest, calendar: calendar
        )
        #expect(schedule.isEmpty)
    }

    @Test("A daily-goal plan trains every day and schedules no sessions")
    func dailyGoalTrainsDaily() {
        let state = makeState(planID: PlanCatalog.dailyGoalID)
        #expect(PlanEngine.schedule(for: state, from: monday, count: 3, calendar: calendar).isEmpty)
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
            #expect(PlanEngine.isTrainingDay(state, date: day, calendar: calendar))
        }
    }

    @Test("An explicit rest day is not a training day for any plan")
    func restDayIsNotATrainingDay() {
        let state = makeState(planID: PlanCatalog.dailyGoalID)
        #expect(PlanEngine.isTrainingDay(state, date: monday, restDays: ["2026-08-03"], calendar: calendar) == false)
    }
}

@Suite("Plan catalog")
struct PlanCatalogTests {

    @Test("An unknown plan id falls back to the free plan instead of trapping")
    func unknownPlanFallsBack() {
        #expect(PlanCatalog.template("retired-plan") == nil)
        #expect(PlanCatalog.templateOrDefault("retired-plan").id == PlanCatalog.dailyGoalID)
    }

    @Test("The published table is reproduced literally, with no scaling")
    func tablePlanIgnoresMax() {
        let low = makeState(planID: "hundred", max: 5)
        let high = makeState(planID: "hundred", max: 200)
        #expect(PlanEngine.sets(for: low, sessionIndex: 0) == PlanEngine.sets(for: high, sessionIndex: 0))
        #expect(PlanEngine.sets(for: low, sessionIndex: 0) == [10, 12, 7, 7, 9])
    }

    @Test("Running past the end of a table repeats the last session")
    func tableClampsAtTheEnd() {
        let state = makeState(planID: "hundred")
        let last = PlanEngine.sets(for: state, sessionIndex: 17)
        #expect(PlanEngine.sets(for: state, sessionIndex: 99) == last)
        #expect(last.isEmpty == false)
    }

    @Test("The pyramid goes up and back down, one rung higher each session")
    func pyramidClimbs() {
        let state = makeState(planID: "pyramid", max: 20)   // base rung 7
        let first = PlanEngine.sets(for: state, sessionIndex: 0)
        #expect(first == [1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1])
        let second = PlanEngine.sets(for: state, sessionIndex: 1)
        #expect(second.max() == 8)
        #expect(second.reduce(0, +) > first.reduce(0, +))
    }

    @Test("Only the daily-goal plan is free")
    func onlyDailyGoalIsFree() {
        #expect(PlanCatalog.all.filter { !$0.isPro }.map(\.id) == [PlanCatalog.dailyGoalID])
    }
}
