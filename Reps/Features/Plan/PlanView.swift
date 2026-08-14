import SwiftUI
import RepsKit

struct PlanView: View {
    @Environment(RepsStore.self) private var store
    @Environment(TabRouter.self) private var router

    @State private var showPicker = false
    @State private var showMaxTest = false
    @State private var showDays = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        if let plan = store.state.plan {
                            progressCard(plan)
                            if PlanEngine.needsMaxTest(plan) { retestCard }
                            shapeCard
                            scheduleCard
                            settingsCard(plan)
                        } else {
                            REmptyState(
                                icon: "calendar",
                                title: "No plan yet",
                                message: "A plan decides how many push-ups to do and when, so you don't have to."
                            )
                            PrimaryButton(title: "CHOOSE A PLAN", systemImage: "calendar") { showPicker = true }
                        }
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .navigationTitle("Plan")
        }
        .sheet(isPresented: $showPicker) { PlanPickerSheet() }
        .sheet(isPresented: $showMaxTest) { MaxTestSheet() }
        .sheet(isPresented: $showDays) { TrainingDaysSheet() }
    }

    // MARK: - Cards

    private func progressCard(_ plan: PlanState) -> some View {
        let template = PlanCatalog.templateOrDefault(plan.planID)
        let perBlock = max(1, template.sessionsPerBlock)
        let fraction = template.kind == .dailyGoal ? 0 : Double(plan.sessionIndex) / Double(perBlock)

        return RCard {
            HStack(spacing: RTheme.Spacing.card) {
                if template.kind == .dailyGoal {
                    RRing(fraction: min(1, Double(store.repsToday) / Double(max(1, plan.dailyGoal))),
                          size: 96, label: "\(store.repsToday)")
                } else {
                    ZStack {
                        RRing(fraction: fraction, size: 96, showsCheckWhenComplete: false)
                        VStack(spacing: 0) {
                            Text("BLOCK \(plan.blockIndex + 1)")
                                .font(RTheme.font(size: 11, weight: .bold))
                                .foregroundStyle(Color.rMutedForeground)
                            Text("\(plan.sessionIndex)")
                                .font(RTheme.font(size: 26, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.rForeground)
                            Text("of \(perBlock)")
                                .font(RTheme.font(size: 11))
                                .foregroundStyle(Color.rMutedForeground)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: RTheme.Spacing.tight) {
                    Text(template.name)
                        .font(RTheme.heading)
                        .foregroundStyle(Color.rForeground)
                    Text(template.summary)
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                    if template.kind != .dailyGoal {
                        Text("Anchor: \(plan.baseMax) max")
                            .font(RTheme.captionMedium)
                            .foregroundStyle(Color.rPrimary)
                            .padding(.top, RTheme.Spacing.tight)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var retestCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "flag.checkered", title: "Block complete")
                Text("You finished the block. Test your max again so the next one is built on what you can do now, not what you could do ten weeks ago.")
                    .font(RTheme.body)
                    .foregroundStyle(Color.rMutedForeground)
                PrimaryButton(title: "TEST MY MAX", systemImage: "flame.fill") { showMaxTest = true }
            }
        }
    }

    /// Sits above the schedule on purpose: flipping it rewrites every row below, and the
    /// prescription is recomputed on render, so the change is visible instantly.
    @ViewBuilder
    private var shapeCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "square.stack.3d.up", title: "Session")
                if store.planHonoursSetCount {
                    SessionShapeControl(setCount: store.setCount) { store.setSetCount($0) }
                } else {
                    Text("This program prescribes its own sets, so it always runs as published.")
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)
                }
            }
        }
    }

    private var scheduleCard: some View {
        let upcoming = store.upcomingSessions(6)
        return RCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(icon: "calendar", title: "Coming up")
                    .padding(RTheme.Spacing.card)

                if upcoming.isEmpty {
                    Text("Nothing scheduled. Pick training days below.")
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)
                        .padding([.horizontal, .bottom], RTheme.Spacing.card)
                } else {
                    ForEach(Array(upcoming.enumerated()), id: \.element.dayKey) { index, session in
                        if index > 0 { Divider().padding(.leading, RTheme.Spacing.card) }
                        HStack(alignment: .top, spacing: RTheme.Spacing.stack) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friendlyDate(session.dayKey))
                                    .font(RTheme.bodyMedium)
                                    .foregroundStyle(index == 0 ? Color.rPrimary : Color.rForeground)
                                Text("\(session.total) push-ups")
                                    .font(RTheme.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.rMutedForeground)
                            }
                            Spacer()
                            Prescription(sets: session.sets, activeIndex: nil)
                        }
                        .padding(RTheme.Spacing.card)
                    }
                }
            }
        }
    }

    private func settingsCard(_ plan: PlanState) -> some View {
        RCard(padding: 0) {
            VStack(spacing: 0) {
                row("Training days", value: weekdaySummary(plan.trainingWeekdays)) { showDays = true }
                Divider().padding(.leading, RTheme.Spacing.card)
                row("Retest max", value: "\(plan.baseMax)") { showMaxTest = true }
                Divider().padding(.leading, RTheme.Spacing.card)
                row("Switch plan", value: PlanCatalog.templateOrDefault(plan.planID).name) { showPicker = true }
            }
        }
    }

    private func row(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(RTheme.body)
                    .foregroundStyle(Color.rForeground)
                Spacer()
                Text(value)
                    .font(RTheme.body)
                    .foregroundStyle(Color.rMutedForeground)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.rMutedForeground)
            }
            .padding(RTheme.Spacing.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func friendlyDate(_ dayKey: String) -> String {
        guard let date = DayKey.date(dayKey) else { return dayKey }
        if dayKey == store.today { return "Today" }
        if dayKey == DayKey.adding(1, to: store.today) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func weekdaySummary(_ days: Set<Int>) -> String {
        guard !days.isEmpty else { return "None" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            .joined(separator: " ")
    }
}
