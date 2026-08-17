import SwiftUI
import RepsKit

/// The screen between tapping START and getting on the floor.
///
/// It exists for one reason: a user whose first set counts zero never opens the app again.
/// Two sentences about where the phone goes and which sensor is running removes almost all
/// of that, and the engine picker is here rather than buried in Settings because the
/// moment you need to change it is the moment it did not work.
struct PlacementSheet: View {
    @Environment(RepsStore.self) private var store
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// Passed in for a free set, which has no plan behind it. For a plan session this is
    /// ignored in favour of the live prescription, so changing the shape on this screen
    /// updates what you are about to do.
    let targets: [Int]
    let onStart: (WorkoutSession) -> Void

    @State private var engine: CountingEngine = .proximity

    /// A plan session re-reads its targets every render. A free set keeps the empty array
    /// it was handed, because a free set has no prescription to reshape.
    private var liveTargets: [Int] {
        targets.isEmpty ? [] : (store.nextSession?.sets ?? targets)
    }

    private var available: [CountingEngine] { RepDetectorFactory.availableEngines() }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        illustration
                        if !targets.isEmpty { prescription }
                        enginePicker
                        explanation
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "I'M READY", systemImage: "play.fill") { start() }
                    .padding(RTheme.Spacing.page)
                    .background(.regularMaterial)
            }
            .navigationTitle(targets.isEmpty ? "Free set" : "Get set up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(.rPrimary)
                }
            }
        }
        .onAppear { engine = resolvedEngine }
    }

    /// Honour the saved preference, but never offer an engine this device cannot run.
    private var resolvedEngine: CountingEngine {
        let saved = store.state.settings.engine
        return available.contains(saved) ? saved : (available.first ?? .manual)
    }

    // Placement is per engine, and depth and proximity are opposites: depth needs the
    // camera under your FACE looking straight up at it, proximity needs the top of the
    // phone under your STERNUM because only the sensor window can feel anything. One
    // shared illustration told depth users to aim the camera at their chest, which meant
    // no face, a failed calibration, and a first set that counted zero.
    private var illustration: some View {
        RCard {
            VStack(spacing: RTheme.Spacing.stack) {
                Image(systemName: engine == .depth ? "faceid" : "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.rPrimary)
                    .rotationEffect(.degrees(engine == .depth ? 0 : 90))
                Text(placementHeadline)
                    .font(RTheme.bodyMedium)
                    .foregroundStyle(Color.rForeground)
                    .multilineTextAlignment(.center)
                Text(placementDetail)
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var placementHeadline: String {
        switch engine {
        case .depth:
            "Phone flat on the floor, screen up, directly under your face"
        case .proximity:
            // The sensor is a few millimetres wide at the *top* of the screen, beside
            // the front camera, and it only reads covered under about 5 cm. "Under
            // your chest" is not precise enough: it puts the middle of the phone under
            // the sternum and the sensor itself under the collarbone, which never gets
            // low enough. The top of the phone has to point at your feet so the sensor
            // sits under the part of you that actually reaches the floor.
            "Phone flat on the floor, screen up, top of the phone pointing at your feet"
        case .manual:
            "Phone flat on the floor, under your face"
        }
    }

    private var placementDetail: String {
        switch engine {
        case .depth:
            "The camera should look straight up at you. It says tracking once it sees your face, and counting is automatic from there."
        case .proximity:
            "The sensor is the small window at the top of the screen. Put that directly under your sternum, and lower until your chest brushes it."
        case .manual:
            "Tap the screen with your nose at the bottom of each rep, or count with a finger or a volume button."
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
            SectionHeader(icon: "sensor", title: "Counting")
            HStack(spacing: RTheme.Spacing.inline) {
                ForEach(available, id: \.self) { option in
                    // No engine is gated. Counting is the app; charging for the one engine
                    // that counts reliably would put the paywall in front of the product.
                    let locked = false
                    Button {
                        if locked {
                            dismiss()
                            router.showPaywall = true
                        } else {
                            engine = option
                            store.update { $0.engine = option }
                            Haptics.select()
                        }
                    } label: {
                        VStack(spacing: RTheme.Spacing.tight) {
                            Image(systemName: locked ? "lock.fill" : option.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(option.label)
                                .font(RTheme.captionMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RTheme.Spacing.stack)
                        .background(
                            engine == option ? Color.rPrimary : Color.rMuted,
                            in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
                        )
                        .foregroundStyle(engine == option ? .white : Color.rMutedForeground)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
            Text(engine.explanation)
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)

            if engine == .proximity {
                // The single most common "is it broken?" moment in the whole app. Saying
                // it before the first set is worth more than any amount of support email.
                Label(
                    "The screen going black at the bottom of each rep is the sensor working, not a bug.",
                    systemImage: "info.circle"
                )
                .font(RTheme.caption)
                .foregroundStyle(Color.rPrimary)
            }
        }
        .padding(RTheme.Spacing.stack)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous))
    }

    /// Today's work, and the one control that changes it.
    ///
    /// The shape switch lives here and not only in Settings because this is the screen
    /// where the decision actually gets made. "I don't have fifteen minutes today" is a
    /// thought people have with the phone already in their hand, on the floor.
    private var prescription: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
            SectionHeader(icon: "list.number", title: "Today")

            HStack(alignment: .firstTextBaseline, spacing: RTheme.Spacing.inline) {
                Prescription(sets: liveTargets, activeIndex: 0)
                Spacer(minLength: 0)
                Text(summary)
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
            }

            if store.planHonoursSetCount {
                SessionShapeControl(setCount: store.setCount, isCompact: true) {
                    store.setSetCount($0)
                }
            }
        }
        .padding(RTheme.Spacing.card)
        .background(Color.rCard, in: RoundedRectangle(cornerRadius: RTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RTheme.Radius.card, style: .continuous)
                .stroke(Color.rCardBorder, lineWidth: 1)
        )
    }

    private var summary: String {
        let total = liveTargets.reduce(0, +)
        guard liveTargets.count > 1 else { return "\(total) push-ups in one set" }
        return "\(total) across \(liveTargets.count) sets, \(store.state.settings.restSeconds)s rest"
    }

    private func start() {
        Haptics.tap()
        var preferences = store.state.settings
        preferences.engine = engine
        let plan = store.state.plan
        // `liveTargets`, not `targets` — the shape may have been changed on this very
        // screen, and starting the session the user was looking at is the whole point.
        onStart(WorkoutSession(
            targets: liveTargets,
            planID: targets.isEmpty ? nil : plan?.planID,
            planSessionIndex: targets.isEmpty ? nil : store.nextSession?.sessionIndex,
            preferences: preferences
        ))
    }
}
