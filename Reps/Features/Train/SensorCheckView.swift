import SwiftUI
import UIKit
import RepsKit

/// A live readout of the proximity sensor, with no rep machine in the way.
///
/// This exists because "it doesn't count" has three completely different causes and no way
/// to tell them apart from the session screen: the sensor never fires, the sensor fires but
/// the debounce rejects it, or the sensor fires and the session drops it. This screen
/// removes the last two from the picture — every raw state change is shown and counted.
///
/// **It has to be audible and haptic, not just visual.** iOS blanks the display the moment
/// the sensor reads covered, so a purely visual test would go dark exactly when the thing
/// you are testing starts working. The tick you feel is the real output here; the numbers
/// are for afterwards.
@MainActor
@Observable
final class SensorProbe {
    private(set) var isNear = false
    private(set) var changes = 0
    private(set) var isMonitoring = false
    /// Seconds the sensor has been continuously covered, for the current cover only.
    private(set) var lastCoveredFor: TimeInterval?

    private var observer: NSObjectProtocol?
    private var coveredAt: TimeInterval?

    func start() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        isMonitoring = device.isProximityMonitoringEnabled
        isNear = device.proximityState

        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.record(UIDevice.current.proximityState)
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        isMonitoring = false
    }

    func reset() {
        changes = 0
        lastCoveredFor = nil
    }

    private func record(_ near: Bool) {
        guard near != isNear else { return }
        isNear = near
        changes += 1
        let now = ProcessInfo.processInfo.systemUptime
        if near {
            coveredAt = now
            Haptics.rep()
        } else {
            if let coveredAt { lastCoveredFor = now - coveredAt }
            coveredAt = nil
            Haptics.tap()
        }
    }
}

/// Reachable from Settings and from the placement sheet. Not debug-only on purpose: a user
/// whose case hoods the sensor needs this more than we do.
struct SensorCheckView: View {
    @State private var probe = SensorProbe()

    var body: some View {
        ZStack {
            Color.rBackground.ignoresSafeArea()
            VStack(spacing: RTheme.Spacing.card) {
                indicator
                readout
                instructions
                Spacer()
            }
            .padding(RTheme.Spacing.page)
        }
        .navigationTitle("Sensor check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { probe.start() }
        .onDisappear { probe.stop() }
    }

    private var indicator: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            Circle()
                .fill(probe.isNear ? Color.rPrimary : Color.rMuted)
                .frame(width: 140, height: 140)
                .overlay {
                    Text(probe.isNear ? "COVERED" : "CLEAR")
                        .font(RTheme.captionMedium)
                        .foregroundStyle(probe.isNear ? .white : Color.rMutedForeground)
                }
                .animation(.easeOut(duration: 0.12), value: probe.isNear)

            Text("\(probe.changes)")
                .font(RTheme.font(size: 44, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.rForeground)
            Text("state changes")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
        }
    }

    @ViewBuilder
    private var readout: some View {
        VStack(spacing: 8) {
            row("Monitoring enabled", probe.isMonitoring ? "yes" : "NO")
            if let held = probe.lastCoveredFor {
                // The rep machine needs 180ms of hold before it accepts an edge, so a
                // cover shorter than that would be counted as chatter and dropped.
                row("Last cover held", String(format: "%.2fs", held))
            }
            Button("Reset count") { probe.reset() }
                .font(RTheme.captionMedium)
                .tint(.rPrimary)
                .padding(.top, 4)
        }
        .padding(RTheme.Spacing.card)
        .frame(maxWidth: .infinity)
        .background(Color.rCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.rCardBorder))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(RTheme.body).foregroundStyle(Color.rMutedForeground)
            Spacer()
            Text(value).font(RTheme.bodyMedium).monospacedDigit()
                .foregroundStyle(Color.rForeground)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The sensor is at the top of the screen, next to the front camera. Not the middle.")
                .font(RTheme.bodyMedium)
                .foregroundStyle(Color.rForeground)
            Text("Wave your hand a couple of centimetres over that spot. You should feel a tick and see the number climb, even though the screen goes dark while it is covered.")
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
            Text("It reads covered under about 5 cm and clear again past 10 cm, so it needs to be genuinely close.")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
