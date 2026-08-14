import Testing
import Foundation
@testable import RepsKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// 2026-08-03, a Monday.
private var monday: Date { DayKey.date("2026-08-03", calendar: utc)! }

private func workout(_ day: String, sets: [(Int, Int)], planID: String? = nil) -> Workout {
    Workout(
        dayKey: day,
        startedAt: DayKey.date(day, calendar: utc)!,
        sets: sets.map {
            CompletedSet(target: $0.0, completed: $0.1,
                         startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        },
        planID: planID
    )
}

@Suite("Reminder plan")
struct ReminderPlanTests {

    private func state(
        planID: String = PlanCatalog.adaptiveID,
        goal: Int = 100,
        weekdays: Set<Int> = [2, 4, 6],
        workouts: [Workout] = [],
        restDays: Set<String> = []
    ) -> PersistedState {
        var state = PersistedState()
        state.workouts = workouts
        state.restDays = restDays
        state.plan = PlanState(
            planID: planID, baseMax: 20, trainingWeekdays: weekdays,
            startedOn: "2026-08-03", dailyGoal: goal
        )
        return state
    }

    @Test("No plan means no reminders at all")
    func noPlanNoReminders() {
        var bare = PersistedState()
        bare.plan = nil
        #expect(ReminderPlan.daysToRemind(state: bare, horizon: 7, calendar: utc, now: monday).isEmpty)
    }

    @Test("Only training days are reminded")
    func onlyTrainingDays() {
        let days = ReminderPlan.daysToRemind(
            state: state(), horizon: 7, calendar: utc, now: monday
        )
        #expect(days.map(\.dayKey) == ["2026-08-03", "2026-08-05", "2026-08-07"])
    }

    @Test("A finished session is not reminded about")
    func completedDayIsSkipped() {
        // The whole reason reminders are re-armed rather than repeating: a nag that fires
        // after you already trained is how an app teaches people to ignore it.
        let done = workout("2026-08-03", sets: [(30, 30)], planID: PlanCatalog.adaptiveID)
        let days = ReminderPlan.daysToRemind(
            state: state(workouts: [done]), horizon: 7, calendar: utc, now: monday
        )
        #expect(days.first?.dayKey == "2026-08-05")
    }

    @Test("A partial session still gets reminded — it is not done")
    func partialDayIsStillReminded() {
        let partial = workout("2026-08-03", sets: [(30, 11)], planID: PlanCatalog.adaptiveID)
        let days = ReminderPlan.daysToRemind(
            state: state(workouts: [partial]), horizon: 7, calendar: utc, now: monday
        )
        #expect(days.first?.dayKey == "2026-08-03")
    }

    @Test("Rest days are never reminded")
    func restDaysAreSkipped() {
        let days = ReminderPlan.daysToRemind(
            state: state(restDays: ["2026-08-05"]), horizon: 7, calendar: utc, now: monday
        )
        #expect(days.map(\.dayKey).contains("2026-08-05") == false)
    }

    @Test("Reminders stay inside the horizon")
    func horizonIsRespected() {
        let days = ReminderPlan.daysToRemind(
            state: state(), horizon: 3, calendar: utc, now: monday
        )
        #expect(days.allSatisfy { $0.dayKey <= "2026-08-05" })
    }

    @Test("A daily-goal plan reminds every non-rest day until the goal is met")
    func dailyGoalReminders() {
        let days = ReminderPlan.daysToRemind(
            state: state(planID: PlanCatalog.dailyGoalID, goal: 100),
            horizon: 3, calendar: utc, now: monday
        )
        #expect(days.map(\.dayKey) == ["2026-08-03", "2026-08-04", "2026-08-05"])
        #expect(days.first?.title == "100 push-ups")
    }

    @Test("A daily goal already met is not reminded, and a partial one counts down")
    func dailyGoalCountsDown() {
        let partial = workout("2026-08-03", sets: [(0, 60)])
        let days = ReminderPlan.daysToRemind(
            state: state(planID: PlanCatalog.dailyGoalID, goal: 100, workouts: [partial]),
            horizon: 2, calendar: utc, now: monday
        )
        #expect(days.first?.title == "40 to go")

        let met = workout("2026-08-03", sets: [(0, 120)])
        let after = ReminderPlan.daysToRemind(
            state: state(planID: PlanCatalog.dailyGoalID, goal: 100, workouts: [met]),
            horizon: 2, calendar: utc, now: monday
        )
        #expect(after.map(\.dayKey) == ["2026-08-04"])
    }

    @Test("A one-set reminder does not repeat the number twice")
    func singleSetCopy() {
        // The title already carries the number. Listing "60" again as the set breakdown
        // reads like a bug.
        let days = ReminderPlan.daysToRemind(state: state(), horizon: 2, calendar: utc, now: monday)
        // A 20-rep max at 0.60 is a 12-rep working set.
        #expect(days.first?.title == "12 push-ups today")
        #expect(days.first?.body == "One set. Two minutes.")
    }

    @Test("A multi-set reminder lists the sets")
    func multiSetCopy() {
        var multi = state()
        multi.plan?.setCount = 3
        let days = ReminderPlan.daysToRemind(state: multi, horizon: 2, calendar: utc, now: monday)
        #expect(days.first?.body.contains("·") == true)
    }

    @Test("A streak is only mentioned once it is worth protecting")
    func streakLineAppearsLate() {
        let short = ReminderPlan.daysToRemind(state: state(), horizon: 2, calendar: utc, now: monday)
        #expect(short.first?.body.contains("streak") == false)

        let building = [
            workout("2026-07-31", sets: [(0, 50)]),
            workout("2026-08-01", sets: [(0, 50)]),
            workout("2026-08-02", sets: [(0, 50)])
        ]
        let long = ReminderPlan.daysToRemind(
            state: state(workouts: building), horizon: 2, calendar: utc, now: monday
        )
        #expect(long.first?.body.contains("3 day streak") == true)
    }
}
