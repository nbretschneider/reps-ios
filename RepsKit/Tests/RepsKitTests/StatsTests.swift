import Testing
import Foundation
@testable import RepsKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func workout(_ day: String, sets: [Int]) -> Workout {
    Workout(
        dayKey: day,
        startedAt: DayKey.date(day, calendar: utc) ?? Date(timeIntervalSinceReferenceDate: 0),
        sets: sets.map {
            CompletedSet(target: $0, completed: $0,
                         startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        }
    )
}

@Suite("Day keys")
struct DayKeyTests {

    @Test("Keys round-trip through dates")
    func roundTrip() {
        let key = "2026-08-14"
        let date = DayKey.date(key, calendar: utc)
        #expect(date != nil)
        #expect(DayKey.make(date!, calendar: utc) == key)
    }

    @Test("Arithmetic crosses month and year boundaries")
    func arithmetic() {
        #expect(DayKey.adding(1, to: "2026-08-31", calendar: utc) == "2026-09-01")
        #expect(DayKey.adding(-1, to: "2026-01-01", calendar: utc) == "2025-12-31")
        #expect(DayKey.adding(1, to: "2028-02-28", calendar: utc) == "2028-02-29")   // leap year
    }

    @Test("Ranges are inclusive, ordered, and empty when inverted")
    func ranges() {
        #expect(DayKey.range(from: "2026-08-01", through: "2026-08-03", calendar: utc)
                == ["2026-08-01", "2026-08-02", "2026-08-03"])
        #expect(DayKey.range(from: "2026-08-03", through: "2026-08-01", calendar: utc).isEmpty)
        #expect(DayKey.range(from: "2026-08-01", through: "2026-08-01", calendar: utc).count == 1)
    }

    @Test("Lexicographic order matches chronological order")
    func sortsChronologically() {
        // The whole reason day keys are zero-padded strings: sorting them is sorting time.
        let keys = ["2026-12-01", "2026-02-09", "2027-01-01", "2026-02-10"]
        #expect(keys.sorted() == ["2026-02-09", "2026-02-10", "2026-12-01", "2027-01-01"])
    }

    @Test("An unparseable key yields nil rather than a wrong date")
    func rejectsGarbage() {
        #expect(DayKey.date("not-a-day", calendar: utc) == nil)
        #expect(DayKey.adding(1, to: "nonsense", calendar: utc) == nil)
        #expect(DayKey.weekday("2026-08-03", calendar: utc) == 2)   // Monday
    }
}

@Suite("Totals and series")
struct TotalsTests {

    @Test("Reps are summed per day across multiple sessions")
    func sumsPerDay() {
        let workouts = [
            workout("2026-08-01", sets: [20, 20]),
            workout("2026-08-01", sets: [10]),
            workout("2026-08-02", sets: [30])
        ]
        #expect(Stats.repsByDay(workouts) == ["2026-08-01": 50, "2026-08-02": 30])
        #expect(Stats.total(workouts, from: "2026-08-01", through: "2026-08-02") == 80)
        #expect(Stats.total(workouts, from: "2026-08-02", through: "2026-08-02") == 30)
    }

    @Test("A series is dense: days with no workout appear as zero")
    func seriesIsDense() {
        let series = Stats.series(
            [workout("2026-08-02", sets: [40])],
            from: "2026-08-01", through: "2026-08-03",
            goal: { _ in 100 }, calendar: utc
        )
        #expect(series.map(\.reps) == [0, 40, 0])
        #expect(series.map(\.dayKey) == ["2026-08-01", "2026-08-02", "2026-08-03"])
        #expect(series[1].fraction == 0.4)
        #expect(series.allSatisfy { !$0.hitGoal })
    }

    @Test("Rest days are flagged but still carry any reps that happened anyway")
    func restDaysKeepTheirReps() {
        let series = Stats.series(
            [workout("2026-08-02", sets: [15])],
            from: "2026-08-01", through: "2026-08-02",
            goal: { _ in 100 }, restDays: ["2026-08-02"], calendar: utc
        )
        #expect(series[1].isRest)
        #expect(series[1].reps == 15)
    }

    @Test("A zero goal treats any reps at all as complete")
    func zeroGoalIsSatisfiedByAnything() {
        let point = DayPoint(dayKey: "2026-08-01", reps: 3, goal: 0, isRest: false)
        #expect(point.fraction == 1)
        #expect(point.hitGoal == false)   // no goal means nothing to hit
    }

    @Test("Averages exclude rest days from the denominator, not just the numerator")
    func averageExcludesRestDays() {
        let workouts = [workout("2026-08-01", sets: [100]), workout("2026-08-03", sets: [100])]
        // Four days, one of them rest: 200 over 3 available days.
        let average = Stats.average(
            workouts, from: "2026-08-01", through: "2026-08-04",
            restDays: ["2026-08-02"], calendar: utc
        )
        #expect(average == 67)
        // Without the rest day it would be 200 over 4.
        #expect(Stats.average(workouts, from: "2026-08-01", through: "2026-08-04", calendar: utc) == 50)
    }
}

@Suite("Streaks")
struct StreakTests {

    @Test("Consecutive trained days count")
    func countsConsecutiveDays() {
        let trained: Set<String> = ["2026-08-01", "2026-08-02", "2026-08-03"]
        #expect(Stats.streak(trainedDays: trained, restDays: [], today: "2026-08-03", calendar: utc) == 3)
    }

    @Test("Today does not break a streak until it is over")
    func todayIsForgiven() {
        // Opening the app in the morning must not show a zero it has not earned yet.
        let trained: Set<String> = ["2026-08-01", "2026-08-02"]
        #expect(Stats.streak(trainedDays: trained, restDays: [], today: "2026-08-03", calendar: utc) == 2)
    }

    @Test("A missed day that is not a rest day breaks the streak")
    func gapBreaksIt() {
        let trained: Set<String> = ["2026-08-01", "2026-08-04", "2026-08-05"]
        #expect(Stats.streak(trainedDays: trained, restDays: [], today: "2026-08-05", calendar: utc) == 2)
    }

    @Test("A prescribed rest day passes through without building or breaking")
    func restDaysArePassedThrough() {
        let trained: Set<String> = ["2026-08-01", "2026-08-02", "2026-08-04"]
        let streak = Stats.streak(
            trainedDays: trained, restDays: ["2026-08-03"], today: "2026-08-04", calendar: utc
        )
        #expect(streak == 3)   // the rest day is not counted, but it does not reset either
    }

    @Test("No history is a zero streak, not a crash")
    func emptyIsZero() {
        #expect(Stats.streak(trainedDays: [], restDays: [], today: "2026-08-05", calendar: utc) == 0)
        #expect(Stats.longestStreak(trainedDays: [], restDays: [], calendar: utc) == 0)
    }

    @Test("The longest streak is found even when it is not the current one")
    func longestIsHistorical() {
        let trained: Set<String> = [
            "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04",   // four
            "2026-08-10", "2026-08-11"                                 // two
        ]
        #expect(Stats.longestStreak(trainedDays: trained, restDays: [], calendar: utc) == 4)
    }
}

@Suite("Records")
struct RecordsTests {

    @Test("Best set and best day are tracked separately")
    func bestSetVersusBestDay() {
        let records = Stats.records([
            workout("2026-08-01", sets: [60]),                // one big set
            workout("2026-08-02", sets: [30, 30, 30])         // a bigger day
        ], calendar: utc)
        #expect(records.bestSet == 60)
        #expect(records.bestSetDayKey == "2026-08-01")
        #expect(records.bestDay == 90)
        #expect(records.bestDayKey == "2026-08-02")
        #expect(records.totalReps == 150)
        #expect(records.totalSessions == 2)
    }

    @Test("A tied record stays on the day that set it first")
    func tiesKeepTheOriginal() {
        let records = Stats.records([
            workout("2026-08-05", sets: [50]),
            workout("2026-08-01", sets: [50])
        ], calendar: utc)
        #expect(records.bestSetDayKey == "2026-08-01")
        #expect(records.bestDayKey == "2026-08-01")
    }

    @Test("No history yields empty records rather than nil handling at every call site")
    func emptyRecords() {
        #expect(Stats.records([], calendar: utc) == .empty)
    }
}

@Suite("Set and workout arithmetic")
struct WorkoutArithmeticTests {

    @Test("A partial set is a real result, not a failure to record")
    func partialSetIsRecorded() {
        let set = CompletedSet(target: 30, completed: 24,
                               startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        #expect(set.completed == 24)
        #expect(set.hitTarget == false)
    }

    @Test("A free set has no target and therefore always hits it")
    func freeSetAlwaysHits() {
        let set = CompletedSet(target: 0, completed: 12,
                               startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .manual)
        #expect(set.hitTarget)
    }

    @Test("A session is complete only when every set hit its target")
    func completionRequiresEverySet() {
        let done = Workout(dayKey: "2026-08-01", startedAt: Date(timeIntervalSinceReferenceDate: 0), sets: [
            CompletedSet(target: 10, completed: 10, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity),
            CompletedSet(target: 10, completed: 12, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        ])
        #expect(done.isComplete)

        let short = Workout(dayKey: "2026-08-01", startedAt: Date(timeIntervalSinceReferenceDate: 0), sets: [
            CompletedSet(target: 10, completed: 10, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity),
            CompletedSet(target: 10, completed: 9, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        ])
        #expect(short.isComplete == false)
        #expect(short.totalReps == 19)
        #expect(short.bestSet == 10)
    }

    @Test("An empty session is not complete")
    func emptySessionIsNotComplete() {
        let empty = Workout(dayKey: "2026-08-01", startedAt: Date(timeIntervalSinceReferenceDate: 0), sets: [])
        #expect(empty.isComplete == false)
    }

    @Test("Average depth is nil when nothing measured it, never zero")
    func unmeasuredDepthIsNil() {
        let proximity = Workout(dayKey: "2026-08-01", startedAt: Date(timeIntervalSinceReferenceDate: 0), sets: [
            CompletedSet(target: 10, completed: 10, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity)
        ])
        #expect(proximity.averageDepth == nil)

        let measured = Workout(dayKey: "2026-08-01", startedAt: Date(timeIntervalSinceReferenceDate: 0), sets: [
            // Binary-exact fractions, so the assertion tests the mean and not the
            // floating-point representation of 0.9.
            CompletedSet(target: 10, completed: 10, startedAt: Date(timeIntervalSinceReferenceDate: 0),
                         averageDepth: 1.0, engine: .depth),
            CompletedSet(target: 10, completed: 10, startedAt: Date(timeIntervalSinceReferenceDate: 0),
                         averageDepth: 0.5, engine: .depth)
        ])
        #expect(measured.averageDepth == 0.75)
    }

    @Test("Tempo needs enough reps and time to mean anything")
    func tempoGuardsAgainstNonsense() {
        let instant = CompletedSet(target: 1, completed: 1,
                                   startedAt: Date(timeIntervalSinceReferenceDate: 0),
                                   duration: 0.2, engine: .proximity)
        #expect(instant.tempo == nil)

        let real = CompletedSet(target: 30, completed: 30,
                                startedAt: Date(timeIntervalSinceReferenceDate: 0),
                                duration: 60, engine: .proximity)
        #expect(real.tempo == 30)
    }
}
