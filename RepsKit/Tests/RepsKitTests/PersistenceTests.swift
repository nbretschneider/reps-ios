import Testing
import Foundation
@testable import RepsKit

/// An in-memory `FileStore`, so persistence tests need no simulator and no temp directory.
/// A class because the repository is a value type that holds it by reference.
private final class MemoryFileStore: FileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var directories: Set<String> = []
    /// Paths that should fail on write, to exercise the "save failed" paths.
    var failWritesTo: Set<String> = []

    func read(_ url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = storage[url.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failWritesTo.contains(url.lastPathComponent) else { throw CocoaError(.fileWriteUnknown) }
        storage[url.path] = data
    }

    func remove(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        storage[url.path] = nil
    }

    func contentsOfDirectory(_ url: URL) throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        return storage.keys
            .filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
            .sorted()
            .map { URL(fileURLWithPath: $0) }
    }

    func createDirectory(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        directories.insert(url.path)
    }

    func exists(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[url.path] != nil || directories.contains(url.path)
    }

    func overwrite(_ url: URL, with data: Data) {
        lock.lock(); defer { lock.unlock() }
        storage[url.path] = data
    }

    var fileCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }
}

private func makeRepository() -> (RepsRepository, MemoryFileStore) {
    let files = MemoryFileStore()
    let root = URL(fileURLWithPath: "/container/Data")
    return (RepsRepository(root: root, files: files), files)
}

private func sampleWorkout(id: UUID = UUID(), day: String = "2026-08-14", reps: Int = 30) -> Workout {
    Workout(
        id: id,
        dayKey: day,
        startedAt: Date(timeIntervalSinceReferenceDate: 1_000.123),
        sets: [CompletedSet(target: reps, completed: reps,
                            startedAt: Date(timeIntervalSinceReferenceDate: 1_000.123), engine: .proximity)]
    )
}

@Suite("Date coding")
struct DateCodingTests {

    @Test("Sub-second precision survives a round trip")
    func subSecondPrecisionSurvives() throws {
        // The bug this guards: `.iso8601` and `.secondsSince1970` both lose enough here
        // that `==` on a reloaded state fails, and `Date`'s description rounds to whole
        // seconds so the failure is invisible in a debugger.
        struct Box: Codable, Equatable { var date: Date }
        let original = Box(date: Date(timeIntervalSinceReferenceDate: 1_234.567))
        let data = try StoredDate.makeEncoder().encode(original)
        let decoded = try StoredDate.makeDecoder().decode(Box.self, from: data)
        #expect(decoded == original)
    }

    @Test("Dates encode as integer milliseconds, not a formatted string")
    func encodesAsInteger() throws {
        struct Box: Codable { var date: Date }
        let data = try StoredDate.makeEncoder().encode(Box(date: Date(timeIntervalSinceReferenceDate: 2)))
        #expect(String(data: data, encoding: .utf8) == #"{"date":2000}"#)
    }

    @Test("A full state round-trips to an identical value")
    func stateRoundTrips() throws {
        var state = PersistedState()
        state.workouts = [sampleWorkout()]
        state.maxTests = [MaxTest(reps: 42, takenAt: Date(timeIntervalSinceReferenceDate: 9.876), dayKey: "2026-08-14")]
        state.restDays = ["2026-08-10"]
        state.plan = PlanState(planID: PlanCatalog.adaptiveID, baseMax: 42, startedOn: "2026-08-14")
        state.settings = Preferences(engine: .depth, voice: .everyFifth, restSeconds: 90)

        let data = try StoredDate.makeEncoder().encode(state)
        let decoded = try StoredDate.makeDecoder().decode(PersistedState.self, from: data)
        #expect(decoded == state)
    }

    @Test("Per-rep depth survives a round trip, rep for rep")
    func repTravelsRoundTrip() throws {
        // The histogram is drawn straight off this array, so an encoder that reordered or
        // rounded it would show the user a distribution that never happened.
        let travels = [0.281, 0.274, 0.2695, 0.31, 0.226]
        var state = PersistedState()
        state.workouts = [Workout(
            dayKey: "2026-08-14",
            startedAt: Date(timeIntervalSinceReferenceDate: 1.5),
            sets: [CompletedSet(target: 30, completed: 5,
                                startedAt: Date(timeIntervalSinceReferenceDate: 1.5),
                                averageTravel: 0.272, repTravels: travels, engine: .depth)]
        )]

        let data = try StoredDate.makeEncoder().encode(state)
        let decoded = try StoredDate.makeDecoder().decode(PersistedState.self, from: data)
        #expect(decoded == state)
        #expect(decoded.workouts.first?.sets.first?.repTravels == travels)
    }

    @Test("A climb plan's step and ceiling survive a round trip")
    func climbSettingsRoundTrip() throws {
        var state = PersistedState()
        state.plan = PlanState(planID: PlanCatalog.climbID, baseMax: 40, startedOn: "2026-09-01",
                               dailyGoal: 40, climbStep: 3, climbCeiling: 75)

        let data = try StoredDate.makeEncoder().encode(state)
        let decoded = try StoredDate.makeDecoder().decode(PersistedState.self, from: data)
        #expect(decoded == state)
        #expect(decoded.plan?.climbStep == 3)
        #expect(decoded.plan?.climbCeiling == 75)
    }
}

@Suite("Schema tolerance")
struct SchemaToleranceTests {

    @Test("A state file written before preferences existed still decodes")
    func missingOptionalFieldsDecode() throws {
        // The rule that keeps a bad decode from becoming a dead end: new fields are
        // optional, forever. This is the shape of a v1 file with nothing but workouts.
        let json = #"{"schemaVersion":1,"workouts":[],"maxTests":[],"restDays":[]}"#
        let state = try StoredDate.makeDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(state.plan == nil)
        #expect(state.settings == Preferences())      // defaults, not a crash
        #expect(state.isFirstRun)
    }

    @Test("A set recorded before per-rep depth existed still decodes")
    func missingRepTravelsDecode() throws {
        // Every set already on a user's phone looks like this. Nil has to mean "not
        // measured" and render as nothing, never as an empty distribution or 0 cm.
        let json = """
        {"schemaVersion":1,"restDays":[],"maxTests":[],"workouts":[
          {"id":"5E7E1E90-0000-4000-8000-000000000001","dayKey":"2026-08-14",
           "startedAt":0,"sets":[
             {"id":"5E7E1E90-0000-4000-8000-000000000002","target":30,"completed":30,
              "startedAt":0,"duration":60,"restAfter":0,"averageDepth":0.82,
              "engine":"depth"}]}]}
        """
        let state = try StoredDate.makeDecoder().decode(PersistedState.self, from: Data(json.utf8))
        let set = try #require(state.workouts.first?.sets.first)
        #expect(set.repTravels == nil)
        #expect(set.averageDepth == 0.82)
        #expect(state.workouts.first?.repTravels.isEmpty == true)
    }

    @Test("Onboarding completion is remembered independently of having a plan")
    func onboardingFlagIsIndependent() {
        var state = PersistedState()
        #expect(state.isFirstRun)
        state = StateReducer.apply(.completeOnboarding, to: state)
        #expect(state.isFirstRun == false)
        #expect(state.plan == nil)   // a user can finish setup without picking a plan
    }
}

@Suite("Reducer idempotency")
struct ReducerTests {

    @Test("Adding the same workout twice is a no-op, not a duplicate")
    func addWorkoutIsIdempotent() {
        // This is the invariant the whole spool design rests on: a crash between "state
        // saved" and "spool unlinked" re-applies every envelope.
        let workout = sampleWorkout()
        var state = PersistedState()
        state = StateReducer.apply(.addWorkout(workout), to: state)
        state = StateReducer.apply(.addWorkout(workout), to: state)
        #expect(state.workouts.count == 1)
        #expect(state.reps(on: "2026-08-14") == 30)
    }

    @Test("Re-adding an edited workout updates it in place")
    func addWorkoutUpserts() {
        let id = UUID()
        var state = StateReducer.apply(.addWorkout(sampleWorkout(id: id, reps: 30)), to: PersistedState())
        state = StateReducer.apply(.addWorkout(sampleWorkout(id: id, reps: 45)), to: state)
        #expect(state.workouts.count == 1)
        #expect(state.reps(on: "2026-08-14") == 45)
    }

    @Test("Deleting a workout twice is a no-op")
    func deleteIsIdempotent() {
        let id = UUID()
        var state = StateReducer.apply(.addWorkout(sampleWorkout(id: id)), to: PersistedState())
        state = StateReducer.apply(.deleteWorkout(id), to: state)
        state = StateReducer.apply(.deleteWorkout(id), to: state)
        #expect(state.workouts.isEmpty)
    }

    @Test("Rest days toggle to an absolute value, never a flip")
    func restDayIsAbsolute() {
        // A `.toggleRestDay` case would be the classic non-idempotent mutation, and
        // replaying it after a crash would silently invert the day.
        var state = PersistedState()
        state = StateReducer.apply(.setRestDay(dayKey: "2026-08-10", isRest: true), to: state)
        state = StateReducer.apply(.setRestDay(dayKey: "2026-08-10", isRest: true), to: state)
        #expect(state.restDays == ["2026-08-10"])
        state = StateReducer.apply(.setRestDay(dayKey: "2026-08-10", isRest: false), to: state)
        #expect(state.restDays.isEmpty)
    }

    @Test("The plan is persisted as a whole replacement, so replay is safe")
    func planIsReplacedNotAdvanced() {
        let advanced = PlanState(planID: PlanCatalog.adaptiveID, baseMax: 100, sessionIndex: 5, startedOn: "2026-08-01")
        var state = PersistedState()
        state = StateReducer.apply(.setPlan(advanced), to: state)
        state = StateReducer.apply(.setPlan(advanced), to: state)
        #expect(state.plan?.sessionIndex == 5)
    }

    @Test("Envelopes are folded in creation order, not filesystem order")
    func envelopesFoldInOrder() {
        let id = UUID()
        let early = MutationEnvelope(
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            mutation: .addWorkout(sampleWorkout(id: id, reps: 10))
        )
        let late = MutationEnvelope(
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            mutation: .addWorkout(sampleWorkout(id: id, reps: 99))
        )
        // Handed over backwards, as a directory listing routinely would.
        let state = StateReducer.apply([late, early], to: PersistedState())
        #expect(state.reps(on: "2026-08-14") == 99)
    }
}

@Suite("Repository")
struct RepositoryTests {

    @Test("State survives a save and load")
    func savesAndLoads() throws {
        let (repository, _) = makeRepository()
        var state = try repository.loadState()
        state = StateReducer.apply(.addWorkout(sampleWorkout()), to: state)
        try repository.saveState(state)
        #expect(try repository.loadState() == state)
    }

    @Test("First run returns an empty state rather than throwing")
    func firstRunIsEmpty() throws {
        let (repository, _) = makeRepository()
        let state = try repository.loadState()
        #expect(state.workouts.isEmpty)
        #expect(state.isFirstRun)
    }

    @Test("A corrupt state file falls back to the previous generation and is quarantined")
    func corruptFileFallsBack() throws {
        let (repository, files) = makeRepository()
        var state = try repository.loadState()
        state = StateReducer.apply(.addWorkout(sampleWorkout(reps: 30)), to: state)
        try repository.saveState(state)

        // A second save rotates the good file into state.prev.json.
        state = StateReducer.apply(.addWorkout(sampleWorkout(id: UUID(), day: "2026-08-15", reps: 40)), to: state)
        try repository.saveState(state)

        files.overwrite(URL(fileURLWithPath: "/container/Data/state.json"), with: Data("{ truncated".utf8))

        let recovered = try repository.loadState()
        #expect(recovered.reps(on: "2026-08-14") == 30)
        // The corrupt bytes are kept, never overwritten — that is the only copy of
        // whatever the decode bug was.
        #expect(files.fileCount >= 2)
    }

    @Test("With no fallback available, a corrupt file throws instead of returning empty")
    func corruptWithNoFallbackThrows() throws {
        let (repository, files) = makeRepository()
        _ = try repository.loadState()
        try repository.saveState(PersistedState())
        files.overwrite(URL(fileURLWithPath: "/container/Data/state.json"), with: Data("{ truncated".utf8))
        try? files.remove(URL(fileURLWithPath: "/container/Data/state.prev.json"))

        // Returning an empty state here would look exactly like "your history is gone",
        // and the next save would make that true.
        #expect(throws: RepositoryError.self) { try repository.loadState() }
    }

    @Test("A spooled mutation is folded into state and only then unlinked")
    func drainFoldsThenUnlinks() throws {
        let (repository, _) = makeRepository()
        let state = try repository.loadState()
        try repository.saveState(state)
        try repository.appendMutation(.addWorkout(sampleWorkout(reps: 25)))

        #expect(try repository.readSpool().count == 1)
        let drained = try repository.drain(into: state)
        #expect(drained.reps(on: "2026-08-14") == 25)
        #expect(try repository.readSpool().isEmpty)
        #expect(try repository.loadState().reps(on: "2026-08-14") == 25)
    }

    @Test("A failed save leaves the spool intact so nothing is lost")
    func failedSaveKeepsTheSpool() throws {
        let (repository, files) = makeRepository()
        let state = try repository.loadState()
        try repository.appendMutation(.addWorkout(sampleWorkout()))
        files.failWritesTo = ["state.json"]

        #expect(throws: (any Error).self) { try repository.drain(into: state) }
        // Unlinking first would have destroyed the only record of that set.
        #expect(try repository.readSpool().count == 1)
    }

    @Test("Draining twice produces the same state")
    func drainIsIdempotent() throws {
        let (repository, _) = makeRepository()
        let workout = sampleWorkout()
        let state = try repository.loadState()
        try repository.appendMutation(.addWorkout(workout))
        try repository.appendMutation(.addWorkout(workout))   // the replay a crash would cause
        let drained = try repository.drain(into: state)
        #expect(drained.workouts.count == 1)
    }

    @Test("An unreadable envelope is dropped rather than wedging every future drain")
    func garbageEnvelopeIsDropped() throws {
        let (repository, files) = makeRepository()
        try repository.appendMutation(.addWorkout(sampleWorkout(reps: 11)))
        files.overwrite(
            URL(fileURLWithPath: "/container/Data/spool/\(UUID().uuidString).json"),
            with: Data("not json".utf8)
        )
        let drained = try repository.drain(into: try repository.loadState())
        #expect(drained.reps(on: "2026-08-14") == 11)
        #expect(try repository.readSpool().isEmpty)
    }

    @Test("The widget's snapshot read includes mutations spooled since it was written")
    func snapshotIncludesSpool() throws {
        let (repository, _) = makeRepository()
        try repository.writeSnapshot(RepsSnapshot(
            dayKey: "2026-08-14", repsToday: 40, goalToday: 100, streak: 3,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        ))
        try repository.appendMutation(.addWorkout(sampleWorkout(day: "2026-08-14", reps: 20)))
        // A set logged from the widget has to show in the widget without waiting for the
        // app to be launched.
        #expect(repository.snapshotIncludingSpool()?.repsToday == 60)
    }

    @Test("Spooled work for another day does not leak into today's snapshot")
    func snapshotIgnoresOtherDays() throws {
        let (repository, _) = makeRepository()
        try repository.writeSnapshot(RepsSnapshot(
            dayKey: "2026-08-14", repsToday: 40, goalToday: 100, streak: 3,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        ))
        try repository.appendMutation(.addWorkout(sampleWorkout(day: "2026-08-13", reps: 20)))
        #expect(repository.snapshotIncludingSpool()?.repsToday == 40)
    }

    @Test("No snapshot yet reads as nil, so the widget renders its placeholder")
    func missingSnapshotIsNil() {
        let (repository, _) = makeRepository()
        #expect(repository.readSnapshot() == nil)
        #expect(repository.snapshotIncludingSpool() == nil)
    }
}

@Suite("Export")
struct ExportTests {

    @Test("A JSON backup restores to an identical state")
    func backupRoundTrips() throws {
        let (repository, _) = makeRepository()
        var state = PersistedState()
        state = StateReducer.apply(.addWorkout(sampleWorkout()), to: state)
        state = StateReducer.apply(.setRestDay(dayKey: "2026-08-10", isRest: true), to: state)
        let data = try repository.exportJSON(state)
        #expect(try repository.importJSON(data) == state)
    }

    @Test("CSV has a header and one row per set")
    func csvShape() {
        let (repository, _) = makeRepository()
        var state = PersistedState()
        state = StateReducer.apply(.addWorkout(Workout(
            dayKey: "2026-08-14",
            startedAt: Date(timeIntervalSinceReferenceDate: 0),
            sets: [
                CompletedSet(target: 30, completed: 30, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .proximity),
                CompletedSet(target: 20, completed: 18, startedAt: Date(timeIntervalSinceReferenceDate: 0), engine: .manual)
            ]
        )), to: state)

        let lines = repository.exportCSV(state).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("day,started_at"))
        #expect(lines[2].contains("20,18"))
    }
}
