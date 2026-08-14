import Foundation

/// Declared once in `project.yml` and mirrored here. `scripts/preflight.sh` greps both and
/// fails if they drift — a silent mismatch gives the widget its own empty container and
/// looks exactly like data loss.
public enum AppGroup {
    public static let identifier = "group.com.gradedays.reps"
}

/// The filesystem operations the repository needs, so tests can run against memory.
public protocol FileStore: Sendable {
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    func contentsOfDirectory(_ url: URL) throws -> [URL]
    func createDirectory(_ url: URL) throws
    func exists(_ url: URL) -> Bool
}

public struct DiskFileStore: FileStore {
    public init() {}

    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func write(_ data: Data, to url: URL) throws {
        // Atomic: a half-written state.json is the one failure the fallback file cannot
        // recover from, because it would look like valid-but-truncated JSON.
        try data.write(to: url, options: [.atomic])
    }

    public func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

public enum RepositoryError: Error, Equatable {
    case noContainer
    case decodeFailed(String)
}

/// Reads and writes everything the app owns.
///
/// The widget extension can write (it has a "log a set" button), so two processes touch
/// the same data. Rather than locking around a shared file, the design removes the shared
/// mutable file:
///
/// | File | Writers | Readers |
/// |---|---|---|
/// | `Data/state.json` | app only | app |
/// | `Data/state.prev.json` | app only | app (corruption fallback) |
/// | `Data/spool/<uuid>.json` | app **and** extension | app (drain), widget (render) |
/// | `Data/snapshot.json` | app only | widget, control |
///
/// The extension's entire write surface is one immutable file per mutation, named by a
/// UUID no other process will pick. No `NSFileCoordinator`, no locks, no lost updates.
public struct RepsRepository: Sendable {
    private let root: URL
    private let files: FileStore
    private let encoder = StoredDate.makeEncoder()
    private let decoder = StoredDate.makeDecoder()

    public init(root: URL, files: FileStore = DiskFileStore()) {
        self.root = root
        self.files = files
    }

    /// The app-group container, or nil when the entitlement is missing — which in practice
    /// means the app group in `project.yml` and `AppGroup.identifier` have drifted.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    public static func make(files: FileStore = DiskFileStore()) throws -> RepsRepository {
        guard let container = containerURL() else { throw RepositoryError.noContainer }
        return RepsRepository(root: container.appendingPathComponent("Data", isDirectory: true), files: files)
    }

    var stateURL: URL { root.appendingPathComponent("state.json") }
    var previousStateURL: URL { root.appendingPathComponent("state.prev.json") }
    var snapshotURL: URL { root.appendingPathComponent("snapshot.json") }
    var spoolURL: URL { root.appendingPathComponent("spool", isDirectory: true) }

    // MARK: - State

    /// Load, falling back to the previous good file if the current one will not decode.
    ///
    /// A corrupt file is **quarantined, never overwritten**. Throwing here is what puts the
    /// store into `.loadFailed` and blocks all writes, which is the only thing standing
    /// between a decode bug and silently replacing a user's history with an empty state.
    public func loadState() throws -> PersistedState {
        try files.createDirectory(root)
        try files.createDirectory(spoolURL)

        guard files.exists(stateURL) else {
            // Genuinely first run, or the fallback survived a quarantine.
            if files.exists(previousStateURL), let recovered = try? decodeState(previousStateURL) {
                return recovered
            }
            return PersistedState()
        }

        do {
            return try decodeState(stateURL)
        } catch {
            try? quarantine(stateURL)
            if files.exists(previousStateURL), let recovered = try? decodeState(previousStateURL) {
                return recovered
            }
            throw RepositoryError.decodeFailed(String(describing: error))
        }
    }

    /// Save, rotating the current file into `state.prev.json` first so there is always one
    /// known-good generation behind the live one.
    public func saveState(_ state: PersistedState) throws {
        try files.createDirectory(root)
        if files.exists(stateURL), let current = try? files.read(stateURL) {
            try? files.write(current, to: previousStateURL)
        }
        try files.write(try encoder.encode(state), to: stateURL)
    }

    private func decodeState(_ url: URL) throws -> PersistedState {
        try decoder.decode(PersistedState.self, from: try files.read(url))
    }

    private func quarantine(_ url: URL) throws {
        let name = "corrupt-\(UUID().uuidString)-\(url.lastPathComponent)"
        let data = try files.read(url)
        try files.write(data, to: root.appendingPathComponent(name))
        try files.remove(url)
    }

    // MARK: - Spool

    /// Append one mutation. Safe from either process: the filename is a fresh UUID, so
    /// two writers can never target the same path.
    public func appendMutation(_ mutation: Mutation, at date: Date = Date()) throws {
        try files.createDirectory(spoolURL)
        let envelope = MutationEnvelope(createdAt: date, mutation: mutation)
        try files.write(
            try encoder.encode(envelope),
            to: spoolURL.appendingPathComponent("\(envelope.id.uuidString).json")
        )
    }

    public func readSpool() throws -> [(url: URL, envelope: MutationEnvelope)] {
        guard files.exists(spoolURL) else { return [] }
        return try files.contentsOfDirectory(spoolURL)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? files.read(url),
                      let envelope = try? decoder.decode(MutationEnvelope.self, from: data)
                else {
                    // An unreadable envelope is dropped rather than blocking every future
                    // drain. One lost widget tap beats a permanently stuck spool.
                    try? files.remove(url)
                    return nil
                }
                return (url, envelope)
            }
    }

    /// Fold the spool into state and clear it.
    ///
    /// **Order is read → fold → save → then unlink.** Deleting first loses data if the save
    /// fails. Re-applying after a crash is harmless precisely because every mutation is
    /// idempotent.
    @discardableResult
    public func drain(into state: PersistedState) throws -> PersistedState {
        let spooled = try readSpool()
        guard !spooled.isEmpty else { return state }

        let folded = StateReducer.apply(spooled.map(\.envelope), to: state)
        try saveState(folded)
        for entry in spooled { try? files.remove(entry.url) }
        return folded
    }

    // MARK: - Snapshot

    public func writeSnapshot(_ snapshot: RepsSnapshot) throws {
        try files.createDirectory(root)
        try files.write(try encoder.encode(snapshot), to: snapshotURL)
    }

    /// Read the widget's view of the world. Returns nil rather than throwing — a widget
    /// with no snapshot yet should render its placeholder, not an error.
    public func readSnapshot() -> RepsSnapshot? {
        guard files.exists(snapshotURL), let data = try? files.read(snapshotURL) else { return nil }
        return try? decoder.decode(RepsSnapshot.self, from: data)
    }

    /// The widget's read path: the last written snapshot plus anything spooled since,
    /// so a tap in the widget updates the widget without waiting for the app to launch.
    public func snapshotIncludingSpool() -> RepsSnapshot? {
        guard var snapshot = readSnapshot() else { return nil }
        guard let spooled = try? readSpool() else { return snapshot }
        for entry in spooled.sorted(by: { $0.envelope.createdAt < $1.envelope.createdAt }) {
            if case .addWorkout(let workout) = entry.envelope.mutation,
               workout.dayKey == snapshot.dayKey {
                snapshot.repsToday += workout.totalReps
            }
        }
        return snapshot
    }

    // MARK: - Export

    /// The only recovery path in an app with no account and no sync. Shares the
    /// repository's coders on purpose: a backup written with a different date strategy
    /// would restore with shifted timestamps.
    public func exportJSON(_ state: PersistedState) throws -> Data {
        let encoder = StoredDate.makeEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(state)
    }

    public func importJSON(_ data: Data) throws -> PersistedState {
        try decoder.decode(PersistedState.self, from: data)
    }

    /// Flat CSV, one row per set. Deliberately not the JSON backup: this is the format a
    /// spreadsheet opens, and it is lossy on purpose.
    public func exportCSV(_ state: PersistedState) -> String {
        var lines = ["day,started_at,set_index,target,completed,duration_s,engine,depth"]
        let iso = ISO8601DateFormatter()
        for workout in state.workouts.sorted(by: { $0.startedAt < $1.startedAt }) {
            for (index, set) in workout.sets.enumerated() {
                let depth = set.averageDepth.map { String(format: "%.3f", $0) } ?? ""
                lines.append([
                    workout.dayKey,
                    iso.string(from: workout.startedAt),
                    String(index + 1),
                    String(set.target),
                    String(set.completed),
                    String(Int(set.duration.rounded())),
                    set.engine.rawValue,
                    depth
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
