import WidgetKit
import SwiftUI
import AppIntents
import RepsKit

struct RepsEntry: TimelineEntry {
    let date: Date
    let snapshot: RepsSnapshot
}

struct RepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RepsEntry {
        RepsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RepsEntry) -> Void) {
        completion(RepsEntry(date: Date(), snapshot: current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RepsEntry>) -> Void) {
        let entry = RepsEntry(date: Date(), snapshot: current())
        // Refresh at midnight so "today" rolls over even if the app is never opened.
        // Everything else is driven by `WidgetCenter.reloadAllTimelines` from the store.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    /// Reads the app-written snapshot **plus** anything spooled since, so a set logged from
    /// the widget shows in the widget without waiting for the app to launch.
    private func current() -> RepsSnapshot {
        guard let repository = try? RepsRepository.make() else { return .placeholder }
        return repository.snapshotIncludingSpool()
            ?? RepsSnapshot(dayKey: DayKey.today(), repsToday: 0, goalToday: 0, streak: 0, updatedAt: Date())
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RepsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.snapshot.fraction) {
                Image(systemName: "figure.strengthtraining.functional")
            } currentValueLabel: {
                Text("\(entry.snapshot.repsToday)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.snapshot.repsToday) push-ups")
                    .font(.headline)
                    .monospacedDigit()
                Text(entry.snapshot.isRestDay ? "Rest day" : subtitle)
                    .font(.caption)
            }

        case .systemMedium:
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.snapshot.repsToday)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.rForeground)
                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rMutedForeground)
                    Spacer(minLength: 0)
                    // One tap logs a set without opening the app. The extension writes a
                    // spool envelope, never state.json.
                    HStack(spacing: 6) {
                        quickAdd(10)
                        quickAdd(20)
                        quickAdd(30)
                    }
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(spacing: 6) {
                ring
                Text(entry.snapshot.isRestDay ? "Rest day" : subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rMutedForeground)
                    .lineLimit(1)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.rMuted, lineWidth: 9)
            Circle()
                .trim(from: 0, to: entry.snapshot.fraction)
                .stroke(
                    entry.snapshot.fraction >= 1 ? Color.rAccent : Color.rPrimary,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(entry.snapshot.repsToday)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.rForeground)
        }
        .frame(width: 74, height: 74)
    }

    private func quickAdd(_ reps: Int) -> some View {
        Button(intent: LogSetIntent(reps: reps)) {
            Text("+\(reps)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.rPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.rMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if entry.snapshot.isRestDay { return "Rest day" }
        if entry.snapshot.goalToday > 0 {
            let remaining = max(0, entry.snapshot.goalToday - entry.snapshot.repsToday)
            return remaining > 0 ? "\(remaining) to go" : "Done for today"
        }
        return entry.snapshot.streak > 0 ? "\(entry.snapshot.streak) day streak" : "No session yet"
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: RepsProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Color.rBackground, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your push-ups today, and one tap to log more.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

/// Control Center, Action Button, and the Lock Screen. Zero parameters on purpose — a
/// control that needs configuring before it works is a control nobody uses.
struct StartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StartControl") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Push-Ups", systemImage: "figure.strengthtraining.functional")
            }
        }
        .displayName("Start Push-Ups")
        .description("Start today's session from anywhere.")
    }
}

@main
struct RepsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StartControl()
    }
}
