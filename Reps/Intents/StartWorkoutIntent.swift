import AppIntents
import RepsKit

/// "Hey Siri, start my push-ups."
///
/// Compiled into **both** targets: an `AppIntent` has to be in the widget extension for
/// `Button(intent:)` to run in-process. Nothing in this folder may reference app code.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Push-Ups"
    static let description = IntentDescription("Opens Reps and starts today's session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Log a set without opening the app: the widget's one-tap button and the Control Center
/// control both run this.
///
/// It writes a spool file rather than touching `state.json`. The app is the only writer of
/// that file, so an extension mutating it directly is how two processes lose each other's
/// data. A UUID-named envelope no other process will pick has no such problem.
struct LogSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Push-Ups"
    static let description = IntentDescription("Adds a set of push-ups to today without opening Reps.")
    static let openAppWhenRun = false

    @Parameter(title: "Push-ups", default: 20)
    var reps: Int

    init() {}

    init(reps: Int) { self.reps = reps }

    func perform() async throws -> some IntentResult {
        guard reps > 0, let repository = try? RepsRepository.make() else { return .result() }
        let now = Date()
        let workout = Workout(
            dayKey: DayKey.today(now: now),
            startedAt: now,
            sets: [CompletedSet(target: 0, completed: reps, startedAt: now, engine: .manual)]
        )
        try? repository.appendMutation(.addWorkout(workout), at: now)
        return .result()
    }
}

struct RepsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my push-ups in \(.applicationName)",
                "Start a \(.applicationName) session"
            ],
            shortTitle: "Start Push-Ups",
            systemImageName: "figure.strengthtraining.functional"
        )
        AppShortcut(
            intent: LogSetIntent(),
            phrases: ["Log push-ups in \(.applicationName)"],
            shortTitle: "Log Push-Ups",
            systemImageName: "plus.circle.fill"
        )
    }
}
