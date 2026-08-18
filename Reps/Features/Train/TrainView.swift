import SwiftUI
import Charts
import RepsKit

struct TrainView: View {
    @Environment(RepsStore.self) private var store
    @Environment(TabRouter.self) private var router

    @State private var pendingSession: WorkoutSession?
    @State private var showPlacement = false
    @State private var placementTargets: [Int] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        totals
                        // The visual anchor of the tab, above the action cards on purpose:
                        // the number to beat is the motivation, and it is hidden until
                        // there is at least one rep in the window so a brand-new user's
                        // first screen is the start button, not an empty chart.
                        if rangeTotal(days: 13) > 0 { weekCard }
                        todayCard
                        streakCard
                        freeSetCard
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .tint(.rPrimary)
                }
            }
        }
        .sheet(isPresented: $showPlacement) {
            PlacementSheet(targets: placementTargets) { session in
                showPlacement = false
                pendingSession = session
            }
        }
        .fullScreenCover(item: $pendingSession) { session in
            SessionView(session: session, startsMuted: store.state.settings.voice == .silent)
        }
        .onChange(of: router.pendingStart) { _, isPending in
            // One-shot from a widget tap or `reps://start`. Cleared immediately so a
            // second activation does not reopen the session the user just finished.
            guard isPending else { return }
            router.pendingStart = false
            startPlanSession()
        }
    }

    // MARK: - Cards

    private var totals: some View {
        HStack(spacing: RTheme.Spacing.inline) {
            StatTile(label: "Today", value: Format.reps(store.repsToday))
            StatTile(label: "Week", value: Format.reps(rangeTotal(days: 6)))
            StatTile(label: "Month", value: Format.reps(monthTotal))
        }
    }

    @ViewBuilder
    /// The last seven days as bars, under the number that summarizes them.
    ///
    /// The hero is the 7-day daily average, because it is the number worth pushing up: a
    /// single day can be a fluke, the average cannot. Per *calendar* day, same as the
    /// month average on Profile — an "avg a day" label over any other denominator is a
    /// lie. The dashed rule draws that average across the bars, so every bar is visibly
    /// above or below the line to beat. Bars reuse the Profile chart's encoding (goal hit
    /// = accent, otherwise chart pink) rather than inventing a second grammar, one series
    /// means no legend, and the y-axis is hidden because the hero number *is* the scale.
    private var weekCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "chart.bar.fill", title: "Last 7 days")

                HStack(alignment: .firstTextBaseline, spacing: RTheme.Spacing.inline) {
                    Text("\(weekAverage)")
                        .font(RTheme.font(size: 40, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.rForeground)
                    Text("avg a day")
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                    Spacer()
                    trendChip
                }

                Chart {
                    ForEach(weekPoints) { point in
                        BarMark(
                            x: .value("Day", point.dayKey),
                            y: .value("Reps", point.reps)
                        )
                        .cornerRadius(3)
                        .foregroundStyle(point.hitGoal ? Color.rAccent : Color.rChart1)
                    }
                    if weekAverageExact > 0 {
                        RuleMark(y: .value("Average", weekAverageExact))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.rMutedForeground.opacity(0.6))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let key = value.as(String.self) {
                                Text(weekdayLetter(key))
                                    .font(RTheme.caption)
                                    .foregroundStyle(key == store.today ? Color.rForeground : Color.rMutedForeground)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
        }
    }

    /// Up gets the accent and an arrow; down and flat stay muted. Slipping is
    /// information, not an alarm, and an app that shames a slow week gets deleted.
    @ViewBuilder
    private var trendChip: some View {
        if let delta = weekTrendPercent {
            Label(
                "\(delta > 0 ? "+" : "")\(delta)% vs last week",
                systemImage: delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "minus")
            )
            .font(RTheme.captionMedium)
            .foregroundStyle(delta > 0 ? Color.rAccent : Color.rMutedForeground)
        }
    }

    private var todayCard: some View {
        if let next = store.nextSession, next.dayKey == store.today {
            RCard {
                VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                    SectionHeader(icon: "figure.strengthtraining.functional", title: "Today's session")
                    Prescription(sets: next.sets, activeIndex: nil)
                    HStack(alignment: .firstTextBaseline, spacing: RTheme.Spacing.tight) {
                        Text("\(next.total)")
                            .font(RTheme.hero)
                            .monospacedDigit()
                            .foregroundStyle(Color.rForeground)
                        Text(next.sets.count > 1 ? "push-ups in \(next.sets.count) sets" : "push-ups in one set")
                            .font(RTheme.body)
                            .foregroundStyle(Color.rMutedForeground)
                    }
                    PrimaryButton(title: "START TRAINING", systemImage: "play.fill") {
                        Haptics.tap()
                        startPlanSession()
                    }
                }
            }
        } else if store.isRestDayToday {
            RCard {
                VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                    SectionHeader(icon: "moon.zzz.fill", title: "Rest day")
                    Text("Nothing scheduled today. Recovery is when the work lands.")
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)
                    if let next = store.nextSession {
                        Divider()
                        upcoming(next)
                    }
                }
            }
        } else if store.state.plan == nil {
            RCard {
                VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                    SectionHeader(icon: "calendar", title: "No plan yet")
                    Text("Pick a plan and Reps will tell you what to do each day.")
                        .font(RTheme.body)
                        .foregroundStyle(Color.rMutedForeground)
                    PrimaryButton(title: "CHOOSE A PLAN", systemImage: "calendar") {
                        router.selection = .plan
                    }
                }
            }
        } else {
            RCard {
                VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                    SectionHeader(icon: "checkmark.circle.fill", title: "Done for today")
                    Text("\(Format.reps(store.repsToday)) push-ups logged.")
                        .font(RTheme.heading)
                        .foregroundStyle(Color.rAccent)
                    if let next = store.nextSession {
                        Divider()
                        upcoming(next)
                    }
                }
            }
        }
    }

    private func upcoming(_ session: ScheduledSession) -> some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.inline) {
            Text("NEXT TRAINING")
                .font(RTheme.captionMedium)
                .kerning(0.6)
                .foregroundStyle(Color.rPrimary)
            Text(friendlyDate(session.dayKey))
                .font(RTheme.bodyMedium)
                .foregroundStyle(Color.rForeground)
            Prescription(sets: session.sets, activeIndex: nil)
        }
    }

    private var streakCard: some View {
        RCard {
            HStack(spacing: RTheme.Spacing.card) {
                RRing(
                    fraction: store.goalToday > 0 ? Double(store.repsToday) / Double(store.goalToday) : 0,
                    size: 72,
                    label: "\(store.repsToday)",
                    showsCheckWhenComplete: true
                )
                VStack(alignment: .leading, spacing: RTheme.Spacing.tight) {
                    Text("\(store.streak) day\(store.streak == 1 ? "" : "s") streak")
                        .font(RTheme.heading)
                        .foregroundStyle(Color.rForeground)
                    Text(store.streak == 0
                         ? "One session starts it."
                         : "Rest days don't break it.")
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                }
                Spacer()
            }
        }
    }

    private var freeSetCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "infinity", title: "Open set")
                Text("Count push-ups with no target. Counts toward your day either way.")
                    .font(RTheme.body)
                    .foregroundStyle(Color.rMutedForeground)
                Button {
                    Haptics.tap()
                    placementTargets = []
                    showPlacement = true
                } label: {
                    Text("START AN OPEN SET")
                        .font(RTheme.bodyMedium)
                        .foregroundStyle(Color.rPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RTheme.Spacing.stack)
                        .background(
                            RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
                                .stroke(Color.rPrimary, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: - Actions

    private func startPlanSession() {
        placementTargets = store.nextSession?.sets ?? []
        showPlacement = true
    }

    // MARK: - Helpers

    private func rangeTotal(days: Int) -> Int {
        guard let start = DayKey.adding(-days, to: store.today) else { return store.repsToday }
        return Stats.total(store.state.workouts, from: start, through: store.today)
    }

    private var weekPoints: [DayPoint] {
        guard let start = DayKey.adding(-6, to: store.today) else { return [] }
        return store.series(from: start, through: store.today)
    }

    private var weekAverageExact: Double { Double(rangeTotal(days: 6)) / 7 }
    private var weekAverage: Int { Int(weekAverageExact.rounded()) }

    /// Percent change of this 7-day window against the 7 before it, or nil when the
    /// previous week has nothing — a chip against an empty week is division noise, and
    /// hiding it is honest where "+100%" would be theatre.
    private var weekTrendPercent: Int? {
        guard let prevStart = DayKey.adding(-13, to: store.today),
              let prevEnd = DayKey.adding(-7, to: store.today) else { return nil }
        let previous = Stats.total(store.state.workouts, from: prevStart, through: prevEnd)
        guard previous > 0 else { return nil }
        let current = rangeTotal(days: 6)
        return Int((Double(current - previous) / Double(previous) * 100).rounded())
    }

    private func weekdayLetter(_ dayKey: String) -> String {
        guard let date = DayKey.date(dayKey) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    private var monthTotal: Int {
        let start = String(store.today.prefix(7)) + "-01"
        return Stats.total(store.state.workouts, from: start, through: store.today)
    }

    private func friendlyDate(_ dayKey: String) -> String {
        guard let date = DayKey.date(dayKey) else { return dayKey }
        if dayKey == store.today { return "Today" }
        if dayKey == DayKey.adding(1, to: store.today) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// So a session can drive `.fullScreenCover(item:)`. The `AnyObject` default gives
/// `ObjectIdentifier` identity, which is exactly right here: a new session object is a new
/// session.
extension WorkoutSession: Identifiable {}
