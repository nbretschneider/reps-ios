import Foundation

/// Every `Date` persists as **integer milliseconds since the reference date**.
///
/// Do not swap in a stock `dateEncodingStrategy`. `.iso8601` drops sub-second precision,
/// and `.secondsSince1970` shifts the value into the 1970 domain and back, which costs a
/// mantissa bit and breaks `==` on a reloaded state. The failure is near-invisible,
/// because `Date`'s debug description rounds to whole seconds.
public enum StoredDate {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSinceReferenceDate * 1000).rounded()))
        }
        // Stable key order keeps diffs of an exported backup readable, and costs nothing.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let millis = try container.decode(Int64.self)
            return Date(timeIntervalSinceReferenceDate: Double(millis) / 1000)
        }
        return decoder
    }
}
