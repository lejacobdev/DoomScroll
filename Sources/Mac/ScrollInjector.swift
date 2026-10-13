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

    private let clickQueue = DispatchQueue(label: "dev.doomscroll.click", qos: .userInteractive)

    /// Posts a double-click at `point`, or at the pointer when nil, then puts the pointer
    /// back. The clicks are spaced like a person's so iPhone Mirroring sees a double tap.
    func doubleClick(at point: CGPoint?) {
        guard Self.isTrusted else { return }
        clickQueue.async {
            let original = CGEvent(source: nil)?.location
            guard let target = point ?? original else { return }
            for click in 1...2 {
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                          mouseCursorPosition: target, mouseButton: .left) else { continue }
                    e.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                    e.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: type == .leftMouseDown ? 0.03 : 0.07)
                }
            }
            if point != nil, let original { CGWarpMouseCursorPosition(original) }
        }
    }
}
