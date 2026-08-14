import Foundation

/// `"yyyy-MM-dd"` in the user's own calendar.
///
/// Day keys are strings, not `Date`s, and they are **sticky**: assigned when a workout is
/// written and never recomputed. Recomputing would silently move history the first time
/// someone trains in a different timezone.
public enum DayKey {
    /// POSIX locale and a fixed format, so the key is stable regardless of the device's
    /// region settings. The timezone deliberately stays `.current` — the *calendar day* is
    /// local, only the formatting is not.
    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        return f
    }

    public static func make(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: date)
    }

    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        formatter(calendar).date(from: key)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        make(now, calendar: calendar)
    }

    /// `offset` days from `key`. Returns nil only for an unparseable key.
    public static func adding(_ offset: Int, to key: String, calendar: Calendar = .current) -> String? {
        guard let date = date(key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
        return make(moved, calendar: calendar)
    }

    /// Every key from `start` through `end`, inclusive. Empty if the range is inverted.
    public static func range(from start: String, through end: String, calendar: Calendar = .current) -> [String] {
        guard start <= end else { return [] }
        var keys: [String] = []
        var cursor = start
        // Bounded so a malformed key cannot spin forever. Ten years of days is far more
        // than any screen asks for.
        while cursor <= end, keys.count < 3700 {
            keys.append(cursor)
            guard let next = adding(1, to: cursor, calendar: calendar) else { break }
            cursor = next
        }
        return keys
    }

    /// `Calendar` weekday number (1 = Sunday) for a key, or nil if unparseable.
    public static func weekday(_ key: String, calendar: Calendar = .current) -> Int? {
        guard let date = date(key, calendar: calendar) else { return nil }
        return calendar.component(.weekday, from: date)
    }
}
