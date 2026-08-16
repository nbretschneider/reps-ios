import Foundation

/// How much the app talks during a set. The screen is dark at the bottom of every rep in
/// proximity mode, so this is the primary feedback channel, not a decoration.
public enum CountingVoice: String, Codable, Hashable, Sendable, CaseIterable {
    /// Speak every rep. Correct for sets under about twenty.
    case everyRep
    /// Speak every fifth rep. Correct for long sets, where counting each one is noise.
    case everyFifth
    /// Speak only "halfway", "five to go" and "set complete".
    case milestones
    /// Haptics only.
    case silent

    public var label: String {
        switch self {
        case .everyRep: "Every rep"
        case .everyFifth: "Every 5 reps"
        case .milestones: "Milestones only"
        case .silent: "Silent"
        }
    }
}

public struct ReminderSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Minutes after midnight, local time.
    public var minuteOfDay: Int

    public init(isEnabled: Bool = false, minuteOfDay: Int = 18 * 60) {
        self.isEnabled = isEnabled
        self.minuteOfDay = minuteOfDay
    }
}

public struct Preferences: Codable, Hashable, Sendable {
    public var engine: CountingEngine
    public var voice: CountingVoice
    public var hapticsEnabled: Bool
    /// Seconds of rest offered between sets. The timer is a suggestion, always skippable.
    public var restSeconds: Int
    /// Seconds of "get ready" countdown before a set starts. Doubles as the calibration
    /// window in Precision mode, so it must never be zero.
    public var countdownSeconds: Int
    public var reminder: ReminderSettings
    public var syncToHealth: Bool
    /// Body weight in kilograms, used only to estimate active energy for HealthKit.
    /// Nil means "don't estimate" rather than a default that would be wrong for everyone.
    public var bodyWeightKg: Double?

    public init(
        // Depth, not proximity. The proximity sensor only reads covered under about 5 cm
        // and its window is at the top of the phone, so a chest at the bottom of a real
        // push-up frequently never trips it. Face tracking measures the same descent from
        // 20 to 60 cm, which is the range a push-up actually happens in.
        //
        // RepsKit cannot ask whether the hardware exists — that would mean importing ARKit
        // and it is deliberately UIKit-free. `RepDetectorFactory.make` falls back to
        // proximity and then to tap, so this is a preference, not a promise.
        engine: CountingEngine = .depth,
        voice: CountingVoice = .everyRep,
        hapticsEnabled: Bool = true,
        restSeconds: Int = 60,
        countdownSeconds: Int = 3,
        reminder: ReminderSettings = ReminderSettings(),
        syncToHealth: Bool = false,
        bodyWeightKg: Double? = nil
    ) {
        self.engine = engine
        self.voice = voice
        self.hapticsEnabled = hapticsEnabled
        self.restSeconds = restSeconds
        self.countdownSeconds = max(1, countdownSeconds)
        self.reminder = reminder
        self.syncToHealth = syncToHealth
        self.bodyWeightKg = bodyWeightKg
    }
}
