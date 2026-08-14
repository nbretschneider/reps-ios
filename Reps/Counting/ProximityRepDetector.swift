import Foundation
import UIKit
import RepsKit

/// The default engine, and the reason this app exists.
///
/// `UIDevice`'s proximity sensor is a binary "is something within a few centimetres of the
/// earpiece" signal. With the phone flat on the floor under the chest, that is exactly the
/// bottom of a push-up: it reads covered only when the chest is genuinely down, so a half
/// rep does not register at all. There is no threshold to tune, no camera permission, no
/// meaningful battery cost, and it works in a pitch-dark room.
///
/// The cost is that **iOS blanks the display while the sensor is covered.** That is not a
/// bug to work around — the user's chest is on top of the screen at that moment. It does
/// mean audio and haptics are the primary feedback channel, which is why `RepCoach` is not
/// optional polish.
@MainActor
final class ProximityRepDetector: RepDetector {
    static var isAvailable: Bool {
        // The only honest test is to switch it on and see whether iOS keeps it on. A
        // device with no sensor silently refuses.
        let device = UIDevice.current
        let wasEnabled = device.isProximityMonitoringEnabled
        device.isProximityMonitoringEnabled = true
        let supported = device.isProximityMonitoringEnabled
        device.isProximityMonitoringEnabled = wasEnabled
        return supported
    }

    var onRep: ((RepEvent) -> Void)?
    var onPhase: ((RepPhase) -> Void)?
    var onPause: (() -> Void)?

    private(set) var count = 0
    var averageDepth: Double? { nil }   // the sensor is binary; there is no depth to report
    let engine: CountingEngine = .proximity

    private var machine = ProximityRepMachine()
    private var observer: NSObjectProtocol?
    /// Monotonic clock. `Date` would let a mid-set clock adjustment produce a negative
    /// interval, which the debounce would then read as chatter.
    private var startedAt: TimeInterval = 0

    func start() throws {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            throw DetectorError.unavailable(.proximity)
        }

        machine = ProximityRepMachine()
        count = 0
        startedAt = ProcessInfo.processInfo.systemUptime

        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            // The notification carries no payload; the current state is read off the
            // device. Hopping to the main actor explicitly because the queue argument
            // only promises the main *thread*.
            let isNear = UIDevice.current.proximityState
            MainActor.assumeIsolated { self?.handle(isNear: isNear) }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.isProximityMonitoringEnabled = false
    }

    func resetCount() {
        machine.reset()
        count = 0
    }

    private func handle(isNear: Bool) {
        let t = ProcessInfo.processInfo.systemUptime - startedAt
        for output in machine.consume(isNear: isNear, at: t) {
            switch output {
            case .rep(let index, _, let depth):
                count = index
                onRep?(RepEvent(index: index, depth: depth))
            case .phase(let phase, _):
                onPhase?(phase)
            case .abandoned:
                onPause?()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

/// The always-available fallback: one tap, one rep.
///
/// Needed more often than it looks. A thick case can hood the sensor, a long sleeve can
/// cover it, and some people want to count reps of something that is not a push-up.
@MainActor
final class ManualRepDetector: RepDetector {
    static var isAvailable: Bool { true }

    var onRep: ((RepEvent) -> Void)?
    var onPhase: ((RepPhase) -> Void)?
    var onPause: (() -> Void)?

    private(set) var count = 0
    var averageDepth: Double? { nil }
    let engine: CountingEngine = .manual

    func start() throws {}
    func stop() {}
    func resetCount() { count = 0 }

    /// Called by the session view's tap gesture and by the volume-button monitor.
    func registerTap() {
        count += 1
        onPhase?(.down)
        onRep?(RepEvent(index: count, depth: nil))
        onPhase?(.up)
    }
}
