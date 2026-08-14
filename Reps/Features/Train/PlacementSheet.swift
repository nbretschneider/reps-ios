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

    let targets: [Int]
    let onStart: (WorkoutSession) -> Void

    @State private var engine: CountingEngine = .proximity

    private var available: [CountingEngine] { RepDetectorFactory.availableEngines() }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        illustration
                        enginePicker
                        explanation
                        if !targets.isEmpty { prescription }
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

    private var illustration: some View {
        RCard {
            VStack(spacing: RTheme.Spacing.stack) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.rPrimary)
                    .rotationEffect(.degrees(90))
                Text("Phone flat on the floor, screen up, under your chest")
                    .font(RTheme.bodyMedium)
                    .foregroundStyle(Color.rForeground)
                    .multilineTextAlignment(.center)
                Text("Lower until your chest is just above it, then push back up.")
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
            SectionHeader(icon: "sensor", title: "Counting")
            HStack(spacing: RTheme.Spacing.inline) {
                ForEach(available, id: \.self) { option in
                    let locked = option == .depth && !purchases.isPro
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

    private var prescription: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
            SectionHeader(icon: "list.number", title: "Today")
            SetPips(sets: targets, activeIndex: 0)
            Text("\(targets.reduce(0, +)) push-ups across \(targets.count) sets, \(store.state.settings.restSeconds)s rest between.")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
        }
    }

    private func start() {
        Haptics.tap()
        var preferences = store.state.settings
        preferences.engine = engine
        let plan = store.state.plan
        onStart(WorkoutSession(
            targets: targets,
            planID: targets.isEmpty ? nil : plan?.planID,
            planSessionIndex: targets.isEmpty ? nil : store.nextSession?.sessionIndex,
            preferences: preferences
        ))
    }
}
