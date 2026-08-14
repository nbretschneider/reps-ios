import SwiftUI
import Charts
import RepsKit

struct ProfileView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @Environment(RepsStore.self) private var store
    @Environment(PurchaseStore.self) private var purchases
    @Environment(TabRouter.self) private var router

    @State private var scope: Scope = .month
    /// Months back from the current one. Zero is this month.
    @State private var monthOffset = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                        totals
                        monthCard
                        chartCard
                        recordsCard
                        if !purchases.isPro { upgradeCard }
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .tint(.rPrimary)
                }
            }
        }
    }

    // MARK: - Cards

    private var totals: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            HStack(spacing: RTheme.Spacing.inline) {
                StatTile(label: "Today", value: Format.reps(store.repsToday))
                StatTile(label: "Week", value: Format.reps(total(days: 6)))
            }
            HStack(spacing: RTheme.Spacing.inline) {
                StatTile(label: "Month", value: Format.reps(total(days: 29)))
                StatTile(label: "Year", value: Format.reps(total(days: 364)), tint: .rAccent)
            }
        }
    }

    private var monthCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                HStack {
                    Button { monthOffset -= 1; Haptics.select() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .tint(.rPrimary)

                    Spacer()
                    Text(monthTitle)
                        .font(RTheme.heading)
                        .foregroundStyle(Color.rForeground)
                    Spacer()

                    Button { monthOffset += 1; Haptics.select() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .tint(.rPrimary)
                    .disabled(monthOffset >= 0)
                }

                VStack(alignment: .leading, spacing: RTheme.Spacing.tight) {
                    Text(Format.reps(monthPoints.reduce(0) { $0 + $1.reps }))
                        .font(RTheme.hero)
                        .monospacedDigit()
                        .foregroundStyle(Color.rForeground)
                    Text("push-ups this month · avg \(monthAverage) a day")
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                }

                MonthGrid(points: monthPoints, today: store.today)
            }
        }
    }

    private var chartCard: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                Picker("Range", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if purchases.isPro || scope == .week {
                    Chart(chartPoints) { point in
                        BarMark(
                            x: .value("Day", point.dayKey),
                            y: .value("Reps", point.reps)
                        )
                        .cornerRadius(3)
                        .foregroundStyle(point.hitGoal ? Color.rAccent : Color.rChart1)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.rCardBorder)
                            AxisValueLabel().font(RTheme.caption)
                        }
                    }
                    .frame(height: 160)
                } else {
                    lockedChart
                }
            }
        }
    }

    private var lockedChart: some View {
        VStack(spacing: RTheme.Spacing.stack) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.rPrimary)
            Text("Monthly and yearly history is part of Pro.")
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
                .multilineTextAlignment(.center)
            Button("See Pro") { router.showPaywall = true }
                .font(RTheme.bodyMedium)
                .tint(.rPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var recordsCard: some View {
        let records = store.records
        return RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "trophy.fill", title: "Records")
                recordRow("Best set", value: "\(records.bestSet)", detail: records.bestSetDayKey)
                Divider()
                recordRow("Best day", value: Format.reps(records.bestDay), detail: records.bestDayKey)
                Divider()
                recordRow("Longest streak", value: "\(records.longestStreak) days", detail: nil)
                Divider()
                recordRow("All time", value: Format.reps(records.totalReps),
                          detail: "\(records.totalSessions) sessions")
            }
        }
    }

    private func recordRow(_ title: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .font(RTheme.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(Color.rForeground)
                if let detail {
                    Text(detail)
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                }
            }
        }
    }

    private var upgradeCard: some View {
        Button { router.showPaywall = true } label: {
            RCard {
                HStack(spacing: RTheme.Spacing.stack) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.rPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reps Pro")
                            .font(RTheme.heading)
                            .foregroundStyle(Color.rForeground)
                        Text("The classic programs, full history, Precision mode, widgets.")
                            .font(RTheme.caption)
                            .foregroundStyle(Color.rMutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rMutedForeground)
                }
            }
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Data

    private func total(days: Int) -> Int {
        guard let start = DayKey.adding(-days, to: store.today) else { return store.repsToday }
        return Stats.total(store.state.workouts, from: start, through: store.today)
    }

    private var monthInterval: (start: String, end: String) {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        let components = calendar.dateComponents([.year, .month], from: base)
        let first = calendar.date(from: components) ?? base
        let range = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let last = calendar.date(byAdding: .day, value: range - 1, to: first) ?? first
        return (DayKey.make(first), DayKey.make(last))
    }

    private var monthPoints: [DayPoint] {
        let interval = monthInterval
        return store.series(from: interval.start, through: interval.end)
    }

    private var monthTitle: String {
        guard let date = DayKey.date(monthInterval.start) else { return "" }
        return date.formatted(.dateTime.month(.wide).year()).uppercased()
    }

    private var monthAverage: Int {
        let interval = monthInterval
        // Only count days that have happened. Dividing this month's total by 31 on the
        // 3rd produces a number that is technically true and completely useless.
        let end = min(interval.end, store.today)
        guard end >= interval.start else { return 0 }
        return Stats.average(
            store.state.workouts, from: interval.start, through: end,
            restDays: store.state.restDays
        )
    }

    private var chartPoints: [DayPoint] {
        let days: Int = switch scope {
        case .week: 6
        case .month: 29
        case .year: 364
        }
        guard let start = DayKey.adding(-days, to: store.today) else { return [] }
        return store.series(from: start, through: store.today)
    }
}

/// The month calendar of per-day rings — the strongest single element in this category of
/// app, and the reason a monthly view beats a list. A ring you did not fill is visible from
/// across the room.
struct MonthGrid: View {
    let points: [DayPoint]
    let today: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            HStack(spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: RTheme.Spacing.inline) {
                // Blank cells so the first of the month lands under the right weekday.
                ForEach(Array(0..<leadingBlanks), id: \.self) { _ in Color.clear.frame(height: 40) }

                ForEach(points) { point in
                    VStack(spacing: 2) {
                        Text(dayNumber(point.dayKey))
                            .font(RTheme.font(size: 10))
                            .foregroundStyle(point.dayKey == today ? Color.rPrimary : Color.rMutedForeground)
                        ZStack {
                            Circle().stroke(Color.rMuted, lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: point.isRest ? 0 : min(1, ringFraction(point)))
                                .stroke(
                                    point.hitGoal ? Color.rAccent : Color.rPrimary,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            if point.isRest, point.reps == 0 {
                                Text("–")
                                    .font(RTheme.caption)
                                    .foregroundStyle(Color.rMutedForeground)
                            } else {
                                Text("\(point.reps)")
                                    .font(RTheme.font(size: 11, weight: point.reps > 0 ? .semibold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(point.reps > 0 ? Color.rForeground : Color.rMutedForeground)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// With no explicit goal there is nothing to be a fraction *of*, so the ring fills
    /// against the best day in the month instead. That keeps it a comparison rather than
    /// an arbitrary full circle for any day with a single rep.
    private func ringFraction(_ point: DayPoint) -> Double {
        if point.goal > 0 { return point.fraction }
        let best = points.map(\.reps).max() ?? 0
        guard best > 0 else { return 0 }
        return Double(point.reps) / Double(best)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        guard let firstKey = points.first, let weekday = DayKey.weekday(firstKey.dayKey) else { return 0 }
        return (weekday - Calendar.current.firstWeekday + 7) % 7
    }

    private func dayNumber(_ dayKey: String) -> String {
        String(dayKey.suffix(2)).replacingOccurrences(of: "^0", with: "", options: .regularExpression)
    }
}
