import Foundation
import RepsKit

/// One counting engine. The session UI never knows which implementation is running, which
/// is what lets Precision mode ship as a preference rather than a parallel screen.
///
/// Implementations own only the hardware plumbing. All the counting logic they use lives
/// in `RepsKit` as pure state machines over sample streams, so it is tested without a
/// device and cannot drift between engines.
@MainActor
protocol RepDetector: AnyObject {
    /// Can this run on this device right now? Checked before the engine is offered, not
    /// after it fails.
    static var isAvailable: Bool { get }

    /// Fired once per counted rep, on the main actor.
    var onRep: ((RepEvent) -> Void)? { get set }
    /// Fired on every phase change, for the descent haptic and the live UI.
    var onPhase: ((RepPhase) -> Void)? { get set }
    /// Fired when the machine decides a long hold at the bottom was a pause, not a rep.
    var onPause: (() -> Void)? { get set }

    /// Begin delivering samples. Throws if the hardware refuses.
    func start() throws
    func stop()
    /// Zero the count between sets without tearing the hardware down — restarting ARKit
    /// between sets would cost a second of tracking each time.
    func resetCount()

    var count: Int { get }
    /// Mean depth across the current set, or nil for engines that cannot measure it.
    var averageDepth: Double? { get }
    var engine: CountingEngine { get }
}

struct RepEvent {
    var index: Int
    var depth: Double?
}

enum DetectorError: LocalizedError {
    case unavailable(CountingEngine)
    case calibrationFailed
    case cameraDenied

    var errorDescription: String? {
        switch self {
        case .cameraDenied:
            "Camera access is off, so depth counting cannot run. Turn it on in Settings, or switch the engine to Sensor or Tap."
        case .unavailable(let engine):
            switch engine {
            case .proximity: "This iPhone's proximity sensor is not reporting."
            case .depth: "Precision mode needs an iPhone with Face ID."
            case .manual: "Tap counting is unavailable."
            }
        case .calibrationFailed:
            "Could not measure your starting distance. Hold the top of a push-up during the countdown."
        }
    }
}

/// Builds the right detector, falling back rather than failing.
///
/// A user whose preference is Precision mode on a device that cannot do it gets proximity
/// silently — the alternative is an error on a screen where they are already in position.
@MainActor
enum RepDetectorFactory {
    static func make(preferred: CountingEngine) -> any RepDetector {
        switch preferred {
        case .depth where DepthRepDetector.isAvailable:
            return DepthRepDetector()
        case .manual:
            return ManualRepDetector()
        default:
            return ProximityRepDetector.isAvailable ? ProximityRepDetector() : ManualRepDetector()
        }
    }

    static func availableEngines() -> [CountingEngine] {
        var engines: [CountingEngine] = []
        if ProximityRepDetector.isAvailable { engines.append(.proximity) }
        if DepthRepDetector.isAvailable { engines.append(.depth) }
        engines.append(.manual)
        return engines
    }
}

extension CountingEngine {
    var label: String {
        switch self {
        case .proximity: "Sensor"
        case .depth: "Precision"
        case .manual: "Tap"
        }
    }

    var explanation: String {
        switch self {
        case .proximity:
            "Put the phone on the floor under your chest. Lower until your chest is over it, then push. The screen goes dark at the bottom — that is the sensor working."
        case .depth:
            "The front camera measures how far you lower on each rep and scores your depth. The screen stays on."
        case .manual:
            "Tap anywhere on the screen, or press a volume button, once per rep."
        }
    }

    var systemImage: String {
        switch self {
        case .proximity: "dot.radiowaves.up.forward"
        case .depth: "faceid"
        case .manual: "hand.tap.fill"
        }
    }
}
