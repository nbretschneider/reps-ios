import Testing
import Foundation
@testable import RepsKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// A Friday, so the fixed reference day is a training day under the default Mon/Wed/Fri
/// plan. Pinned rather than `Date()` so these assertions cannot start failing on a Sunday.
private let anchor = DayKey.date("2026-08-14", calendar: utc)!

/// The seeded history exists to be photographed. These tests are about the picture: that
/// it is full, that it holds a live streak, and that it is the same picture every run.
@Suite("Demo data")
struct DemoDataTests {

    private func demo() -> PersistedState {
        DemoData.state(today: anchor, calendar: utc)
    }

    @Test("Every screen has something to show")
    func populated() {
        let state = demo()
        #expect(state.hasCompletedOnboarding)
        #expect(state.plan?.planID == PlanCatalog.adaptiveID)
        #expect(state.workouts.count > 80)
        #expect(state.maxTests.count >= 3)

        let records = Stats.records(state.workouts, restDays: [], calendar: utc)
        #expect(records.bestSet > 20)
        #expect(records.totalReps > 1500)
    }

    @Test("History spans the generated window and stops at today")
    func window() {
        let state = demo()
        let keys = state.workouts.map(\.dayKey).sorted()
        let todayKey = DayKey.make(anchor, calendar: utc)
        let firstKey = DayKey.adding(-(DemoData.weeks * 7), to: todayKey, calendar: utc)!

        #expect(keys.first! >= firstKey)
        #expect(keys.last! <= todayKey)
        // Nine months of it, not a fortnight bunched at one end.
        #expect(keys.first! < DayKey.adding(-180, to: todayKey, calendar: utc)!)
    }

    @Test("The streak on the Train tab is worth a screenshot")
    func liveStreak() {
        let state = demo()
        let plan = state.plan!
        let todayKey = DayKey.make(anchor, calendar: utc)
        let trained = Set(Stats.repsByDay(state.workouts).filter { $0.value > 0 }.keys)
        // The same union the store feeds to `Stats.streak`: a day the plan never asked for
        // is not a missed day.
        let rest = PlanEngine.prescribedRestDays(
            for: plan,
            from: DayKey.adding(-400, to: todayKey, calendar: utc)!,
            through: todayKey,
            calendar: utc
        )
        let streak = Stats.streak(trainedDays: trained, restDays: rest, today: todayKey, calendar: utc)
        // Rest days pass through without incrementing, so the floor is the number of
        // *training* days in the missed-session-free tail: three a week.
        #expect(streak >= DemoData.cleanTailDays / 7 * 3)
    }

    @Test("Free sets exist but never consume a scheduled session")
    func freeSets() {
        let state = demo()
        let free = state.workouts.filter { $0.planID == nil }
        #expect(!free.isEmpty)
        #expect(free.allSatisfy { $0.sessionIndex == nil })
    }

    @Test("The same history every run")
    func deterministic() {
        // Not `==` on the states: workout ids are fresh UUIDs. What has to be stable is
        // what a screenshot shows.
        let a = Stats.repsByDay(demo().workouts)
        let b = Stats.repsByDay(demo().workouts)
        #expect(a == b)
    }
}
