import SwiftUI
import ARKit
import RepsKit

/// A live readout of TrueDepth face tracking, with no rep machine in the way.
///
/// The depth twin of `SensorCheckView`, and it exists for the same reason: "it doesn't
/// count" has several causes that are indistinguishable from the session screen. This
/// strips it to the raw question — is a face being tracked, and at what distance — so a
/// failed set can be split into "the camera never saw you" versus "the camera saw you and
/// the session lost it". Unlike the proximity check this one can be visual, because depth
/// mode is the mode where the screen stays on.
@MainActor
@Observable
final class DepthProbe: NSObject, ARSessionDelegate {
    /// Straight-line camera-to-face distance in meters. Nil while no face is tracked.
    private(set) var distance: Double?
    private(set) var frames = 0
    private(set) var minSeen: Double?
    private(set) var maxSeen: Double?

    private let session = ARSession()
    private var lastFrameAt: TimeInterval = 0
    private var staleness: Task<Void, Never>?

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    func start() {
        guard Self.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isLightEstimationEnabled = false
        session.delegate = self
        session.delegateQueue = .main
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // ARKit goes quiet rather than reporting a lost face, so a watchdog turns
        // silence into "NO FACE" instead of freezing the last number on screen.
        staleness = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastFrameAt > 0.6 {
                    self.distance = nil
                }
            }
        }
    }

    func stop() {
        session.pause()
        session.delegate = nil
        staleness?.cancel()
        staleness = nil
        distance = nil
    }

    func reset() {
        frames = 0
        minSeen = nil
        maxSeen = nil
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let t = face.transform.columns.3
        let meters = Double(sqrt(t.x * t.x + t.y * t.y + t.z * t.z))
        let tracked = face.isTracked
        MainActor.assumeIsolated {
            lastFrameAt = ProcessInfo.processInfo.systemUptime
            guard tracked, meters.isFinite, meters > 0 else {
                distance = nil
                return
            }
            distance = meters
            frames += 1
            minSeen = min(minSeen ?? meters, meters)
            maxSeen = max(maxSeen ?? meters, meters)
        }
    }
}

/// Reachable from Settings, beside the sensor check. Not debug-only on purpose: this is
/// the screen that tells a user whether their placement works before a set rides on it.
struct CameraCheckView: View {
    @State private var probe = DepthProbe()

    var body: some View {
        ZStack {
            Color.rBackground.ignoresSafeArea()
            VStack(spacing: RTheme.Spacing.card) {
                if DepthProbe.isSupported {
                    indicator
                    readout
                    instructions
                } else {
                    unsupported
                }
                Spacer()
            }
            .padding(RTheme.Spacing.page)
        }
        .navigationTitle("Camera check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { probe.start() }
        .onDisappear { probe.stop() }
    }

    private var indicator: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            Circle()
                .fill(probe.distance != nil ? Color.rPrimary : Color.rMuted)
                .frame(width: 140, height: 140)
                .overlay {
                    VStack(spacing: 2) {
                        if let distance = probe.distance {
                            Text("\(Int((distance * 100).rounded()))")
                                .font(RTheme.font(size: 44, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("cm")
                                .font(RTheme.captionMedium)
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            Text("NO FACE")
                                .font(RTheme.captionMedium)
                                .foregroundStyle(Color.rMutedForeground)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.12), value: probe.distance != nil)

            Text(probe.distance != nil ? "Tracking your face" : "Looking for a face")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
        }
    }

    private var readout: some View {
        VStack(spacing: 8) {
            row("Face measurements", "\(probe.frames)")
            if let minSeen = probe.minSeen, let maxSeen = probe.maxSeen {
                row("Closest", String(format: "%.0f cm", minSeen * 100))
                row("Farthest", String(format: "%.0f cm", maxSeen * 100))
            }
            Button("Reset") { probe.reset() }
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
            Text("Lay the phone on the floor, screen up, and lean over it the way you would at the top of a push-up.")
                .font(RTheme.bodyMedium)
                .foregroundStyle(Color.rForeground)
            Text("The number is how far your face is from the camera. Lower toward the phone and it should fall smoothly, then rise as you push back up. A push-up usually reads between about 20 and 60.")
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
            Text("If it says NO FACE while you are directly above the phone, slide the phone until your face is over the camera end.")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unsupported: some View {
        Text("This iPhone does not have the Face ID camera that Precision mode uses. The Sensor and Tap engines still work.")
            .font(RTheme.body)
            .foregroundStyle(Color.rMutedForeground)
            .multilineTextAlignment(.center)
            .padding(.top, RTheme.Spacing.page)
    }
}
