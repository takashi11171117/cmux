import Foundation

/// Formats an authored date as the sidebar's short relative label.
///
/// Split out because rendering is one of the three things a row does and every row does it
/// once per SwiftUI pass: computing this in `body` would allocate a `RelativeDateTimeFormatter`
/// per row per pass, and would have to hit the calendar every time. Kept as a value type
/// with an internal static formatter so the allocation happens once and the rendering happens
/// only when the day/hour boundary crosses.
///
/// ```swift
/// GitCommitRelativeDate.string(from: date, now: reference)  // "2時間前"
/// ```
enum GitCommitRelativeDate {
    /// Formats one date.
    ///
    /// - Parameters:
    ///   - date: The authored date to describe.
    ///   - now: Reference "now", so tests can pin the boundary. Defaults to the wall clock.
    /// - Returns: A short relative label such as "2時間前" (ja) or "2 hours ago" (en).
    static func string(from date: Date, now: Date = Date()) -> String {
        // `RelativeDateTimeFormatter` reads the user's locale on the main thread; the row
        // is drawn on main, so the formatter itself is safe to share.
        formatter.localizedString(for: date, relativeTo: now)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
