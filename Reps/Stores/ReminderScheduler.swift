import Foundation
import UserNotifications
import RepsKit

/// One reminder, and only when it is deserved.
///
/// Arms a short run of one-shot triggers and re-arms on every activation, rather than one
/// repeating trigger. iOS gives no chance to compose text at delivery time, and that
/// re-arming is what lets a day whose session is already done be skipped — a daily nag
/// that fires after you trained is how a fitness app teaches people to ignore it.
///
/// The decision of *which* days to arm is `ReminderPlan` in RepsKit and is tested; this is
/// only plumbing.
@MainActor
enum ReminderScheduler {
    private static let prefix = "reps.reminder."
    /// A week of lookahead. Long enough that a user who does not open the app for days
    /// still gets reminded, short enough that the text stays true.
    private static let horizon = 7

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func rearm(state: PersistedState, calendar: Calendar = .current, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        let settings = state.settings.reminder
        guard settings.isEnabled else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let days = ReminderPlan.daysToRemind(
            state: state, horizon: horizon, calendar: calendar, now: now
        )

        for day in days {
            guard let date = DayKey.date(day.dayKey, calendar: calendar) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = settings.minuteOfDay / 60
            components.minute = settings.minuteOfDay % 60
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = day.title
            content.body = day.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: prefix + day.dayKey,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
    }
}
