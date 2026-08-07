import UIKit

/// Subtle haptic feedback while scroll commands stream in, throttled so a
/// 20 Hz command stream doesn't buzz continuously.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let session = UINotificationFeedbackGenerator()
    private var lastTickAt: TimeInterval = 0
    private let tickInterval: TimeInterval = 0.15

    private init() {}

    func scrollTick() {
        let now = Date().timeIntervalSince1970
        guard now - lastTickAt >= tickInterval else { return }
        lastTickAt = now
        tick.impactOccurred(intensity: 0.5)
    }

    func sessionEnded() {
        session.notificationOccurred(.success)
    }
}
