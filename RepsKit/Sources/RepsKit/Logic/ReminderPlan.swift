import Foundation

/// Which days deserve a reminder, and what it should say.
///
/// Pure and tested, because the interesting part is the *suppression*: a reminder that
/// fires on a rest day, or after the session is already done, is how a fitness app trains
/// people to swipe it away without reading it.
public enum ReminderPlan {
    public struct Day: Hashable, Sendable {
        public var dayKey: String
        public var title: String
        public var body: String
    }

    /// Days in `[today, today + horizon)` that should carry a reminder.
    ///
    /// Skipped: rest days, days with no scheduled session, and any day whose work is
    /// already done. Today is included only if it is still unfinished.
    public static func daysToRemind(
        state: PersistedState,
        horizon: Int,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [Day] {
        guard let plan = state.plan, horizon > 0 else { return [] }
        let today = DayKey.make(now, calendar: calendar)
        let trained = Set(state.workouts.filter { $0.totalReps > 0 }.map(\.dayKey))
        let completedPlanDays = Set(state.workouts.filter { $0.planID != nil && $0.isComplete }.map(\.dayKey))
        let template = PlanCatalog.templateOrDefault(plan.planID)
        let streak = Stats.streak(
            trainedDays: trained, restDays: state.restDays, today: today, calendar: calendar
        )

        if template.kind.isDailyNumber {
            // A climb's goal differs per day, so it is resolved per day rather than read
            // once off the plan. That works for the future days in the horizon too: the
            // derivation only scores days that have reps on them, so tomorrow's goal is
            // today's until today is actually finished, at which point it steps.
            let repsByDay = Stats.repsByDay(state.workouts)
            let goalOn: (String) -> Int = { key in
                template.kind == .climb
                    ? PlanEngine.climbGoal(for: plan, on: key, repsByDay: repsByDay, calendar: calendar)
                    : plan.dailyGoal
            }

            return DayKey.range(
                from: today,
                through: DayKey.adding(horizon - 1, to: today, calendar: calendar) ?? today,
                calendar: calendar
            )
            .filter { !state.restDays.contains($0) }
            .filter { state.reps(on: $0) < goalOn($0) }
            .map { key in
                let goal = goalOn(key)
                return Day(
                    dayKey: key,
                    title: key == today && state.reps(on: key) > 0
                        ? "\(goal - state.reps(on: key)) to go"
                        : "\(goal) push-ups",
                    body: streakLine(streak) ?? "Two minutes on the floor and it's done."
                )
            }
        }

        let sessions = PlanEngine.schedule(
            for: plan,
            from: now,
            count: horizon,
            restDays: state.restDays,
            trainedDays: completedPlanDays,
            calendar: calendar
        )

        return sessions
            .filter { $0.dayKey >= today }
            .filter { DayKey.range(from: today, through: DayKey.adding(horizon - 1, to: today, calendar: calendar) ?? today, calendar: calendar).contains($0.dayKey) }
            .map { session in
                Day(
                    dayKey: session.dayKey,
                    title: "\(session.total) push-ups today",
                    // For a single set, `Format.sets` would just repeat the number already
                    // in the title. Say how long it takes instead.
                    body: streakLine(streak)
                        ?? (session.sets.count == 1 ? "One set. Two minutes." : Format.sets(session.sets))
                )
            }
    }

    /// A streak is only worth mentioning once it is worth protecting. Below three days it
    /// reads as pressure rather than progress.
    private static func streakLine(_ streak: Int) -> String? {
        streak >= 3 ? "Keep the \(streak) day streak alive." : nil
    }
}
