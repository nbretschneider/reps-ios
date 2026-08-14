import SwiftUI
import UIKit

/// Haptics are not decoration in this app.
///
/// In proximity mode the screen is dark at the bottom of every rep, so touch and sound are
/// the only channels that reach the user mid-set. Every call here is deliberately cheap
/// and pre-warmed, because a generator created at the moment of a rep fires late enough to
/// feel wrong against the count.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Call when a set is about to start. Warming costs nothing and removes the ~50 ms
    /// first-fire latency that would otherwise land on rep one.
    static func prepareForSet() {
        light.prepare()
        rigid.prepare()
        notification.prepare()
    }

    /// One rep counted. The lightest tap in the app — it fires up to a hundred times a set.
    static func rep() { light.impactOccurred() }

    /// The chest reached the bottom. Confirms the sensor saw the descent, which is the
    /// question a new user actually has on rep one.
    static func descent() { light.impactOccurred(intensity: 0.55) }

    /// Set finished.
    static func setComplete() { notification.notificationOccurred(.success) }

    /// Session finished, or a personal record.
    static func celebrate() { notification.notificationOccurred(.success) }

    /// Rest is over, get back down.
    static func restOver() { rigid.impactOccurred() }

    static func tap() { medium.impactOccurred() }
    static func select() { selection.selectionChanged() }
}
