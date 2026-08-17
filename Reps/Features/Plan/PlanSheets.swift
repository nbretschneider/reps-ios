import SwiftUI
import RepsKit

/// Pick a plan. Pro plans are shown, not hidden — a locked row that explains what it is
/// converts, and a plan the user never knew existed does not.
struct PlanPickerSheet: View {
    @Environment(RepsStore.self) private var store
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var goalDraft = "100"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: RTheme.Spacing.stack) {
                        ForEach(PlanCatalog.all) { template in
                            planRow(template)
                        }
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .navigationTitle("Choose a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(.rPrimary)
                }
            }
        }
    }

    private func planRow(_ template: PlanTemplate) -> some View {
        let isCurrent = store.state.plan?.planID == template.id
        let locked = template.isPro && !purchases.isPro

        return Button {
            if locked {
                dismiss()
                router.showPaywall = true
            } else {
                select(template)
            }
        } label: {
            RCard {
                VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
                    HStack {
                        Text(template.name)
                            .font(RTheme.heading)
                            .foregroundStyle(Color.rForeground)
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.rPrimary)
                        }
                        Spacer()
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.rAccent)
                        }
                    }
                    Text(template.summary)
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)
                        .multilineTextAlignment(.leading)
                    Text(template.kind == .dailyGoal
                         ? "Every day"
                         : "\(template.sessionsPerWeek)x a week · \(template.sessionsPerBlock) sessions a block")
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rPrimary)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    private func select(_ template: PlanTemplate) {
        Haptics.select()
        let existing = store.state.plan
        // Carry the anchor across a plan switch. Re-testing every time someone tries a
        // different program is friction with no payoff.
        let baseMax = existing?.baseMax ?? store.state.latestMax?.reps ?? 10
        store.setPlan(PlanState(
            planID: template.id,
            baseMax: baseMax,
            sessionIndex: 0,
            blockIndex: 0,
            trainingWeekdays: existing?.trainingWeekdays ?? defaultWeekdays(for: template),
            startedOn: store.today,
            dailyGoal: existing?.dailyGoal ?? 100
        ))
        dismiss()
    }

    private func defaultWeekdays(for template: PlanTemplate) -> Set<Int> {
        switch template.sessionsPerWeek {
        case 7: [1, 2, 3, 4, 5, 6, 7]
        case 4: [2, 3, 5, 6]          // Mon Tue Thu Fri
        default: [2, 4, 6]            // Mon Wed Fri
        }
    }
}

/// The max test: one unbroken set, counted by the same engine as everything else.
///
/// The number it produces anchors every adaptive prescription, so it is worth doing
/// properly rather than typing a guess — but typing is still offered, because a user who
/// already knows their max should not have to prove it.
struct MaxTestSheet: View {
    @Environment(RepsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var session: WorkoutSession?
    @State private var typed = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        RCard {
                            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                                SectionHeader(icon: "flame.fill", title: "Max test")
                                Text("As many push-ups as you can in one unbroken set. Stop when your form goes, not when it hurts.")
                                    .font(RTheme.body)
                                    .foregroundStyle(Color.rMutedForeground)
                                PrimaryButton(title: "COUNT MY MAX", systemImage: "play.fill") {
                                    var preferences = store.state.settings
                                    preferences.voice = .everyFifth   // a max set is long; counting each rep is noise
                                    session = WorkoutSession(targets: [], preferences: preferences)
                                }
                            }
                        }

                        RCard {
                            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                                SectionHeader(icon: "keyboard", title: "Or enter it")
                                HStack {
                                    TextField("0", text: $typed)
                                        .keyboardType(.numberPad)
                                        .focused($isFieldFocused)
                                        .font(RTheme.hero)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.rForeground)
                                        .frame(width: 120)
                                    Text("push-ups")
                                        .font(RTheme.body)
                                        .foregroundStyle(Color.rMutedForeground)
                                    Spacer()
                                }
                                Button("Save") { saveTyped() }
                                    .font(RTheme.bodyMedium)
                                    .disabled(parsed == nil)
                            }
                        }
                        .keyboardDoneButton()
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .navigationTitle("Your max")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(.rPrimary)
                }
            }
        }
        .fullScreenCover(item: $session) { session in
            SessionView(session: session)
                .onDisappear {
                    // The free set already saved itself as a workout; this records the
                    // same number as the plan's anchor.
                    let reps = session.completedSets.map(\.completed).max() ?? 0
                    if reps > 0 {
                        store.recordMaxTest(reps: reps)
                        dismiss()
                    }
                }
        }
    }

    private var parsed: Int? {
        guard let value = Int(typed.trimmingCharacters(in: .whitespaces)), value > 0, value < 2000 else { return nil }
        return value
    }

    private func saveTyped() {
        guard let parsed else { return }
        store.recordMaxTest(reps: parsed)
        Haptics.celebrate()
        dismiss()
    }
}

/// Which days the plan trains on.
struct TrainingDaysSheet: View {
    @Environment(RepsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                    Text("Reps schedules sessions on these days and leaves the rest for recovery.")
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)

                    HStack(spacing: RTheme.Spacing.inline) {
                        ForEach(orderedWeekdays, id: \.self) { weekday in
                            Button {
                                if selected.contains(weekday) { selected.remove(weekday) } else { selected.insert(weekday) }
                                Haptics.select()
                            } label: {
                                Text(symbol(weekday))
                                    .font(RTheme.captionMedium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, RTheme.Spacing.stack)
                                    .background(
                                        selected.contains(weekday) ? Color.rPrimary : Color.rMuted,
                                        in: RoundedRectangle(cornerRadius: RTheme.Radius.chip, style: .continuous)
                                    )
                                    .foregroundStyle(selected.contains(weekday) ? .white : Color.rMutedForeground)
                            }
                            .buttonStyle(.pressable)
                        }
                    }

                    if selected.isEmpty {
                        Label("Pick at least one day, or nothing will ever be scheduled.", systemImage: "exclamationmark.triangle")
                            .font(RTheme.caption)
                            .foregroundStyle(Color.rDestructive)
                    }

                    Spacer()
                }
                .padding(RTheme.Spacing.page)
            }
            .navigationTitle("Training days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.tint(.rPrimary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.tint(.rPrimary).disabled(selected.isEmpty)
                }
            }
        }
        .onAppear { selected = store.state.plan?.trainingWeekdays ?? [1, 2, 3, 4, 5, 6, 7] }
    }

    /// Respect the user's locale: a week that starts on Monday should render that way.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func symbol(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
    }

    private func save() {
        guard var plan = store.state.plan else { return dismiss() }
        plan.trainingWeekdays = selected
        store.setPlan(plan)
        dismiss()
    }
}
