import Testing
import Foundation
@testable import RepsKit

private func makeState(
    planID: String = PlanCatalog.adaptiveID,
    max: Int = 100,
    sessionIndex: Int = 0,
    blockIndex: Int = 0,
    failures: Int = 0,
    weekdays: Set<Int> = [2, 4, 6],
    setCount: Int = PlanState.defaultSetCount
) -> PlanState {
    PlanState(
        planID: planID,
        baseMax: max,
        sessionIndex: sessionIndex,
        blockIndex: blockIndex,
        consecutiveFailures: failures,
        trainingWeekdays: weekdays,
        startedOn: "2026-08-03",
        setCount: setCount
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

@Suite("Session shape")
struct SessionShapeTests {

    @Test("A session is one set unless the user asks for more")
    func oneSetIsTheDefault() {
        // The whole product decision, in one assertion. Five sets is fifteen minutes and
        // most people do not have fifteen minutes.
        let state = makeState(max: 100)
        #expect(state.setCount == 1)
        #expect(state.isSingleSet)
        #expect(PlanEngine.sets(for: state, sessionIndex: 0) == [60])
        #expect(PlanEngine.total(for: state, sessionIndex: 0) == 60)
    }

    @Test("Turning on multiple sets gives three by default")
    func threeSetsIsTheMultiDefault() {
        let state = makeState(max: 100, setCount: PlanEngine.defaultMultiSetCount)
        #expect(PlanEngine.sets(for: state, sessionIndex: 0) == [80, 32, 30])
        #expect(state.isSingleSet == false)
    }

    @Test("Five sets still gives the original ladder, unchanged")
    func fiveSetsIsTheOldLadder() {
        // Nothing regresses for someone who turns the shape all the way up.
        let state = makeState(max: 100, setCount: 5)
        #expect(PlanEngine.sets(for: state, sessionIndex: 0) == [80, 30, 28, 30, 30])
        #expect(PlanEngine.total(for: state, sessionIndex: 0) == 198)
    }

    @Test("Every set count from one to five prescribes that many sets")
    func setCountIsHonoured() {
        for count in 1...PlanState.maxSetCount {
            let sets = PlanEngine.sets(for: makeState(max: 100, setCount: count), sessionIndex: 0)
            #expect(sets.count == count)
            #expect(sets.allSatisfy { $0 >= 1 })
        }
    }

    @Test("More sets is always more total volume")
    func moreSetsIsMoreVolume() {
        let totals = (1...PlanState.maxSetCount).map {
            PlanEngine.total(for: makeState(max: 100, setCount: $0), sessionIndex: 0)
        }
        #expect(zip(totals, totals.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("A nonsense set count is clamped rather than trusted")
    func setCountIsClamped() {
        #expect(makeState(setCount: 0).setCount == 1)
        #expect(makeState(setCount: -4).setCount == 1)
        #expect(makeState(setCount: 99).setCount == PlanState.maxSetCount)

        var state = makeState()
        state.setCount = 40
        #expect(state.setCount == PlanState.maxSetCount)
        state.setCount = 0
        #expect(state.setCount == 1)
    }

    @Test("A plan file written before set counts existed reads as one set")
    func decodesWithoutTheField() throws {
        // The rule that keeps a bad decode from becoming a dead end: added fields are
        // optional, forever. This is the shape of a stored plan from before this feature.
        let json = """
        {"planID":"adaptive","baseMax":40,"sessionIndex":2,"blockIndex":0,
         "consecutiveFailures":0,"trainingWeekdays":[2,4,6],"startedOn":"2026-08-03",
         "dailyGoal":100}
        """
        let decoded = try StoredDate.makeDecoder().decode(PlanState.self, from: Data(json.utf8))
        #expect(decoded.setCount == 1)
        #expect(decoded.baseMax == 40)
        #expect(PlanEngine.sets(for: decoded, sessionIndex: 0) == [24])
    }

    @Test("The set count survives a round trip")
    func roundTrips() throws {
        let state = makeState(max: 55, setCount: 3)
        let data = try StoredDate.makeEncoder().encode(state)
        #expect(try StoredDate.makeDecoder().decode(PlanState.self, from: data) == state)
    }

    @Test("Changing the shape is not progression")
    func shapeIsNotProgress() {
        // Switching to three sets must not advance the plan, bank a block, or clear a
        // failure. It is how today looks, not where you are.
        var state = makeState(max: 100, sessionIndex: 7, blockIndex: 2, failures: 1)
        state.setCount = 3
        #expect(state.sessionIndex == 7)
        #expect(state.blockIndex == 2)
        #expect(state.consecutiveFailures == 1)
        #expect(state.baseMax == 100)
    }

    @Test("Only the adaptive plan reshapes; a published program is what it says it is")
    func namedProgramsIgnoreTheShape() {
        for planID in ["hundred", "pyramid"] {
            let single = makeState(planID: planID, max: 40, setCount: 1)
            let multi = makeState(planID: planID, max: 40, setCount: 5)
            #expect(PlanEngine.sets(for: single, sessionIndex: 0)
                    == PlanEngine.sets(for: multi, sessionIndex: 0))
            #expect(PlanEngine.honoursSetCount(single) == false)
        }
        #expect(PlanEngine.honoursSetCount(makeState()))
    }
}

@Suite("Adaptive prescription")
struct AdaptivePrescriptionTests {

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

    @Test("Days the plan never asks for are prescribed rest days")
    func prescribedRestDays() {
        // The bug this exists to prevent: a three-days-a-week plan breaking its own streak
        // every Tuesday, so a perfectly compliant user never sees a number above one.
        let state = makeState(weekdays: [2, 4, 6])   // Mon / Wed / Fri
        let rest = PlanEngine.prescribedRestDays(
            for: state, from: "2026-08-03", through: "2026-08-09", calendar: calendar
        )
        // Mon 3rd, Wed 5th and Fri 7th are training; the other four are rest.
        #expect(rest == ["2026-08-04", "2026-08-06", "2026-08-08", "2026-08-09"])
    }

    @Test("A daily-goal plan prescribes no rest, because it asks for every day")
    func dailyGoalPrescribesNoRest() {
        let state = makeState(planID: PlanCatalog.dailyGoalID)
        #expect(PlanEngine.prescribedRestDays(
            for: state, from: "2026-08-03", through: "2026-08-09", calendar: calendar
        ).isEmpty)
    }

    @Test("A plan with no training days prescribes no rest rather than every day")
    func noWeekdaysPrescribesNoRest() {
        // Returning "every day is rest" here would make an unscheduled plan report an
        // infinite streak, which is worse than reporting none.
        let state = makeState(weekdays: [])
        #expect(PlanEngine.prescribedRestDays(
            for: state, from: "2026-08-03", through: "2026-08-09", calendar: calendar
        ).isEmpty)
    }

    @Test("A three-days-a-week streak survives the days between sessions")
    func streakSurvivesNonTrainingDays() {
        // The integration the fix is actually for: train Mon, Wed, Fri and the streak is
        // three, not one.
        let state = makeState(weekdays: [2, 4, 6])
        let trained: Set<String> = ["2026-08-03", "2026-08-05", "2026-08-07"]
        let rest = PlanEngine.prescribedRestDays(
            for: state, from: "2026-07-01", through: "2026-08-07", calendar: calendar
        )
        #expect(Stats.streak(trainedDays: trained, restDays: rest,
                             today: "2026-08-07", calendar: calendar) == 3)

        // And a genuinely missed session still breaks it: skip Wednesday.
        let missed: Set<String> = ["2026-08-03", "2026-08-07"]
        #expect(Stats.streak(trainedDays: missed, restDays: rest,
                             today: "2026-08-07", calendar: calendar) == 1)
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

    @Test("The default plan is free; the published programs are not")
    func adaptiveAndDailyGoalAreFree() {
        // The daily loop has to be free or the subscription has no habit to attach to.
        // That covers both one-number-a-day plans: a goal you set and a goal that climbs
        // are the same loop with different arithmetic, and gating either would put a
        // paywall in front of the habit the subscription depends on.
        let free = Set(PlanCatalog.all.filter { !$0.isPro }.map(\.id))
        #expect(free == [PlanCatalog.adaptiveID, PlanCatalog.dailyGoalID, PlanCatalog.climbID])
        #expect(PlanCatalog.all.filter { $0.isPro }.map(\.id).sorted() == ["hundred", "pyramid"])
    }

    @Test("Every plan in the catalog produces a session someone can do")
    func everyPlanIsCoherent() {
        // A plan added as a catalog row without a generator behind it shows an empty
        // prescription rather than failing anywhere, so the catalog is walked rather
        // than trusted.
        for template in PlanCatalog.all {
            let state = makeState(planID: template.id, max: 40)
            let sets = PlanEngine.sets(for: state, sessionIndex: 0)
            if template.kind.isDailyNumber {
                #expect(sets.isEmpty, "\(template.id) should prescribe no sets")
                #expect(PlanEngine.total(for: state, sessionIndex: 0) > 0, "\(template.id) needs a number")
            } else {
                #expect(!sets.isEmpty, "\(template.id) prescribed nothing")
                #expect(sets.allSatisfy { $0 > 0 }, "\(template.id) prescribed a zero set")
            }
        }
    }
}
