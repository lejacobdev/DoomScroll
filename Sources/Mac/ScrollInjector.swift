import ApplicationServices
import CoreGraphics
import Foundation

/// Posts real scroll-wheel events system-wide. Requires the Accessibility
/// permission and a non-sandboxed app, which is why the Mac helper is
/// distributed with Developer ID instead of the Mac App Store.
final class ScrollInjector {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Positive `dy` scrolls down (reveals content below), positive `dx`
    /// scrolls right. Natural-scrolling preferences do not apply to
    /// synthetic events, so direction here is absolute.
    func scroll(dx: Int, dy: Int, at point: CGPoint?) {
        guard dx != 0 || dy != 0, Self.isTrusted else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(clamping: -dy), wheel2: Int32(clamping: -dx),
                                  wheel3: 0)
        else { return }
        if let point { event.location = point }
        event.post(tap: .cghidEventTap)
    }
}
