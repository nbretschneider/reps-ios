import Testing
import Foundation
@testable import RepsKit

private let epoch = Date(timeIntervalSinceReferenceDate: 0)

private func mean(_ values: [Double]?) -> Double? {
    guard let values, !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
}

private func set(
    _ travels: [Double]?,
    completed: Int? = nil,
    engine: CountingEngine = .depth
) -> CompletedSet {
    CompletedSet(
        target: 0,
        completed: completed ?? travels?.count ?? 0,
        startedAt: epoch,
        averageTravel: mean(travels),
        repTravels: travels,
        engine: engine
    )
}

private func session(_ travels: [Double]?, day: String) -> Workout {
    Workout(dayKey: day, startedAt: epoch, sets: [set(travels)])
}

@Suite("Depth statistics")
struct DepthStatsTests {

    // MARK: - Centre

    @Test("Median takes the middle rep, and the midpoint of an even set")
    func medianBasics() {
        #expect(DepthStats.median([0.2, 0.3, 0.25]) == 0.25)
        #expect(DepthStats.median([0.2, 0.3]) == 0.25)
        #expect(DepthStats.median([]) == nil)
    }

    @Test("Mean and median disagree when a set falls apart, which is the point")
    func meanAndMedianDiverge() {
        // Ten honest reps and one that stopped at the top. The median says the set was
        // fine; the mean says it was not. Showing both is what makes that visible.
        let travels = Array(repeating: 0.30, count: 10) + [0.06]
        let summary = DepthStats.summary(travels)!
        #expect(summary.median == 0.30)
        #expect(summary.mean < 0.29)
        #expect(summary.shallowest == 0.06)
        #expect(summary.deepest == 0.30)
        #expect(summary.reps == 11)
    }

    @Test("Garbage samples never reach the statistics")
    func filtersNonsense() {
        // A 2 cm "rep" is the user shifting on the floor, and a non-finite one is a
        // ranging glitch. Either in the histogram makes the whole axis unreadable.
        let summary = DepthStats.summary([0.20, 0.02, 0.25, .nan, .infinity])!
        #expect(summary.reps == 2)
        #expect(summary.median == 0.225)
    }

    @Test("Nothing measured reports nothing, not zero")
    func emptyIsNil() {
        // "Not measured" and "no depth" must never render the same. A tapped set has no
        // depth data and must not claim 0 cm.
        #expect(DepthStats.summary([]) == nil)
        #expect(DepthStats.summary([0.01, 0.02]) == nil)
        #expect(DepthStats.histogram([]).isEmpty)
    }

    // MARK: - Histogram

    @Test("Every measured rep lands in exactly one bin")
    func binsAccountForEveryRep() {
        let travels = [0.20, 0.22, 0.25, 0.28, 0.31]
        let bins = DepthStats.histogram(travels)
        #expect(bins.reduce(0) { $0 + $1.count } == travels.count)
        #expect(bins == [
            DepthBin(lowerCm: 15, upperCm: 20, count: 0),
            DepthBin(lowerCm: 20, upperCm: 25, count: 2),
            DepthBin(lowerCm: 25, upperCm: 30, count: 2),
            DepthBin(lowerCm: 30, upperCm: 35, count: 1)
        ])
    }

    @Test("The deepest rep of the session is never dropped off the end")
    func topBinIsClosed() {
        // Bins are half-open so a rep on a boundary is not counted twice, which leaves the
        // very deepest rep with nowhere to go unless the last bin owns its upper edge.
        for travels in [[0.30], [0.25, 0.30], [0.10, 0.45], [0.26, 0.26, 0.27]] {
            let bins = DepthStats.histogram(travels)
            #expect(bins.reduce(0) { $0 + $1.count } == travels.count)
        }
    }

    @Test("A tight set still draws as a distribution")
    func minimumWidth() {
        // Three reps within a centimetre of each other would otherwise be one column,
        // which is a rectangle, not a histogram.
        let bins = DepthStats.histogram([0.26, 0.26, 0.27])
        #expect(bins.count >= 4)
        #expect(bins.reduce(0) { $0 + $1.count } == 3)
    }

    @Test("Bins never run below zero centimetres")
    func noNegativeBins() {
        let bins = DepthStats.histogram([0.06, 0.07])
        #expect(bins.allSatisfy { $0.lowerCm >= 0 })
        #expect(bins.reduce(0) { $0 + $1.count } == 2)
    }

    // MARK: - Over history

    @Test("Only sessions with per-rep data contribute")
    func historyIgnoresUnmeasured() {
        // Every set recorded before per-rep depth existed decodes with nil, and tapped
        // sets never have it. Neither may read as a day of zero depth.
        let workouts = [
            session([0.20, 0.30], day: "2026-09-01"),
            session(nil, day: "2026-09-02"),
            Workout(dayKey: "2026-09-03", startedAt: epoch,
                    sets: [set(nil, completed: 20, engine: .manual)])
        ]
        let byDay = DepthStats.medianByDay(workouts)
        #expect(byDay.count == 1)
        #expect(byDay["2026-09-01"] == 0.25)
        #expect(byDay["2026-09-02"] == nil)
        #expect(byDay["2026-09-03"] == nil)
    }

    @Test("A range pulls every measured rep inside it and none outside")
    func travelsRespectTheRange() {
        let workouts = [
            session([0.20], day: "2026-08-31"),
            session([0.30, 0.32], day: "2026-09-01"),
            session([0.40], day: "2026-09-09")
        ]
        let inside = DepthStats.travels(workouts, from: "2026-09-01", through: "2026-09-08")
        #expect(inside.sorted() == [0.30, 0.32])
    }

    @Test("Today is excluded from the baseline it is compared against")
    func baselineExcludesToday() {
        // Comparing a session to a window containing it flattens the difference the
        // comparison exists to show, and worst on exactly the light-history accounts
        // where the number matters most.
        let today = "2026-09-08"
        let workouts = [
            session([0.20, 0.20], day: "2026-09-02"),
            session([0.20, 0.20], day: "2026-09-03"),
            session([0.40, 0.40], day: today)
        ]
        let result = DepthStats.comparison(
            session: [0.40, 0.40], against: workouts,
            from: "2026-09-02", through: today, excluding: today
        )!
        #expect(result.baseline == 0.20)
        #expect(result.current == 0.40)
        #expect(result.deltaCm == 20)
        #expect(result.isDeeper)
        #expect(result.baselineReps == 4)
    }

    @Test("No history to compare against reports nothing")
    func noBaseline() {
        let today = "2026-09-08"
        let workouts = [session([0.30], day: today)]
        let result = DepthStats.comparison(
            session: [0.30], against: workouts,
            from: "2026-09-01", through: today, excluding: today
        )
        // The user's first measured session has nothing behind it, and an invented
        // baseline of zero would announce a triumphant +30 cm every time.
        #expect(result == nil)
    }

    @Test("Going shallower reports a negative delta rather than hiding it")
    func shallowerIsReported() {
        let today = "2026-09-08"
        let workouts = [
            session([0.30, 0.30], day: "2026-09-04"),
            session([0.20], day: today)
        ]
        let result = DepthStats.comparison(
            session: [0.20], against: workouts,
            from: "2026-09-01", through: today, excluding: today
        )!
        #expect(result.deltaCm == -10)
        #expect(result.isDeeper == false)
    }

    // MARK: - Rollup

    @Test("A session's travels flatten across its sets, weighted by rep")
    func sessionRollup() {
        // A 30-rep set and a 3-rep set are not equal evidence, so the session mean is
        // taken over reps rather than over sets.
        let workout = Workout(dayKey: "2026-09-01", startedAt: epoch, sets: [
            set(Array(repeating: 0.30, count: 9)),
            set([0.10])
        ])
        #expect(workout.repTravels.count == 10)
        #expect(abs(workout.averageTravel! - 0.28) < 0.0001)
    }

    @Test("Sessions older than per-rep depth still report their stored mean")
    func legacyFallback() {
        // The histogram cannot be drawn for these and never will be, but the trend line
        // must not lose the history it already has.
        let legacy = Workout(dayKey: "2026-09-01", startedAt: epoch, sets: [
            CompletedSet(target: 0, completed: 20, startedAt: epoch,
                         averageTravel: 0.26, engine: .depth)
        ])
        #expect(legacy.repTravels.isEmpty)
        #expect(legacy.averageTravel == 0.26)
        #expect(DepthStats.histogram(legacy.repTravels).isEmpty)
    }
}
