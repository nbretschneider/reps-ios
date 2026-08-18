import SwiftUI
import Charts
import RepsKit

/// One day's bar, with everything the chart needs already decided.
///
/// The view does no date formatting and no goal comparison: SwiftUI's `Chart` builder is
/// expensive to type-check, and the first version of this card put the formatting, a
/// conditional mark and the axis closures in one expression, which took the Swift compiler
/// past its limit and failed the build with "failed to produce diagnostic". Precomputing
/// keeps each expression small enough to check quickly.
struct WeekBar: Identifiable, Hashable {
    /// `yyyy-MM-dd`, and the chart's x value — sorting and identity for free.
    let dayKey: String
    let reps: Int
    let hitGoal: Bool
    /// Single-letter weekday label, formatted by the caller.
    let letter: String
    let isToday: Bool

    var id: String { dayKey }
}

/// The Train tab's visual anchor: seven days of bars under the number that summarizes them.
///
/// Pure by the file's convention — it takes values, never the store. The hero is the 7-day
/// daily average rather than any single day, because a day can be a fluke and an average
/// cannot, and it is the number a user can actually push up.
struct WeekChartCard: View {
    let bars: [WeekBar]
    /// Mean reps per calendar day across the window. Same denominator rule as the month
    /// average on Profile: "avg a day" under a 7-day heading has to mean per calendar day.
    let average: Double
    /// Percent change against the previous seven days, or nil when there is nothing to
    /// compare against.
    let trendPercent: Int?

    var body: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                SectionHeader(icon: "chart.bar.fill", title: "Last 7 days")
                hero
                chart
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: RTheme.Spacing.inline) {
            Text("\(Int(average.rounded()))")
                .font(RTheme.font(size: 40, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.rForeground)
            Text("avg a day")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
            Spacer(minLength: 0)
            trendChip
        }
    }

    /// Up gets the accent and an arrow; down and flat stay muted. Slipping is information,
    /// not an alarm, and an app that shames a slow week gets deleted.
    @ViewBuilder
    private var trendChip: some View {
        if let trendPercent {
            Label(trendLabel(trendPercent), systemImage: trendIcon(trendPercent))
                .font(RTheme.captionMedium)
                .foregroundStyle(trendPercent > 0 ? Color.rAccent : Color.rMutedForeground)
        }
    }

    private func trendLabel(_ delta: Int) -> String {
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta)% vs last week"
    }

    private func trendIcon(_ delta: Int) -> String {
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "minus"
    }

    /// Bars reuse the Profile chart's encoding (goal hit = accent, otherwise chart pink)
    /// rather than inventing a second grammar. One series, so no legend. The y-axis is
    /// hidden because the hero number is the scale, and the dashed rule at the average
    /// turns every bar into "above or below the line to beat".
    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Day", bar.dayKey),
                    y: .value("Reps", bar.reps)
                )
                .cornerRadius(3)
                .foregroundStyle(bar.hitGoal ? Color.rAccent : Color.rChart1)
            }
            // A one-or-zero element ForEach rather than an `if`: a conditional inside the
            // chart builder is what made this expression too complex to type-check.
            ForEach(averageRule, id: \.self) { value in
                RuleMark(y: .value("Average", value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.rMutedForeground.opacity(0.6))
            }
        }
        .chartXAxis { xAxis }
        .chartYAxis(.hidden)
        .frame(height: 110)
    }

    private var averageRule: [Double] {
        average > 0 ? [average] : []
    }

    private var xAxis: some AxisContent {
        // Explicit values, not `.automatic`: seven labels must always mean seven days,
        // and automatic marks are free to subsample a categorical axis when space is
        // tight, which would silently drop weekday letters.
        AxisMarks(preset: .aligned, values: bars.map(\.dayKey)) { value in
            AxisValueLabel {
                Text(letter(at: value.index))
                    .font(RTheme.caption)
                    .foregroundStyle(isToday(at: value.index) ? Color.rForeground : Color.rMutedForeground)
            }
        }
    }

    private func letter(at index: Int) -> String {
        bars.indices.contains(index) ? bars[index].letter : ""
    }

    private func isToday(at index: Int) -> Bool {
        bars.indices.contains(index) ? bars[index].isToday : false
    }
}
