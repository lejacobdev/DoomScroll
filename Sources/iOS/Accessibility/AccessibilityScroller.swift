import UIKit
import WebKit
import os

/// Scrolls the frontmost scrollable content **inside this app**.
///
/// Platform reality check (full detail in docs/LIMITATIONS.md): iOS gives a
/// sandboxed app no handle on other processes' UI. The macOS `AXUIElement`
/// accessibility API does not exist on iOS; `UIAccessibility` actions and
/// notifications only reach elements in the current process; and synthesizing
/// HID scroll events (the IOKit route) is private API that will not pass
/// signing. "System-wide" scrolling of Safari/Mail/etc. from a sideloaded app
/// is therefore not achievable — this class scrolls the app's own scroll
/// views and web views, which is the ceiling of what public API allows.
@MainActor
final class AccessibilityScroller {
    private let log = Logger(subsystem: "dev.lejacob.doomscroll", category: "scroller")

    /// Applies a scroll delta (in points) to the best target, trying in order:
    /// 1. The frontmost `UIScrollView` that can actually move (covers SwiftUI
    ///    List/ScrollView, UIKit tables/collections, and WKWebView's own
    ///    scroll view).
    /// 2. `window.scrollBy` JavaScript for web content whose scrolling isn't
    ///    backed by the visible scroll view (e.g. nested scrollable iframes).
    /// 3. Optionally, the in-process accessibility scroll action for custom
    ///    containers that expose scrolling only through accessibility.
    func scroll(byX dx: CGFloat, y dy: CGFloat, allowAccessibilityFallback: Bool) {
        guard dx != 0 || dy != 0 else { return }
        guard let window = activeKeyWindow() else {
            log.debug("No active key window; ignoring scroll command")
            return
        }

        if let scrollView = frontmostScrollView(in: window) {
            apply(dx: dx, dy: dy, to: scrollView)
        } else if let webView = frontmostWebView(in: window) {
            webView.evaluateJavaScript("window.scrollBy(\(dx), \(dy));", completionHandler: nil)
        } else if allowAccessibilityFallback {
            postAccessibilityScroll(dy: dy, in: window)
        } else {
            // No scroll target active — the spec'd behavior is to silently
            // ignore, so the user can leave scroll mode on between screens.
            log.debug("No scrollable target found")
        }
    }

    private func apply(dx: CGFloat, dy: CGFloat, to scrollView: UIScrollView) {
        var offset = scrollView.contentOffset
        let inset = scrollView.adjustedContentInset
        let minX = -inset.left
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        offset.x = min(max(offset.x + dx, minX), maxX)
        offset.y = min(max(offset.y + dy, minY), maxY)
        // No animation: commands arrive at 20 Hz, and animating each step
        // would fight the next one. Direct offset writes read as continuous
        // motion at this rate.
        scrollView.setContentOffset(offset, animated: false)
    }

    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// Depth-first, last-subview-first, so the topmost visible candidate wins;
    /// returns the deepest scroll view that has room to move.
    private func frontmostScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ view: UIView) {
            guard best == nil, !view.isHidden, view.alpha > 0.01 else { return }
            for subview in view.subviews.reversed() {
                visit(subview)
            }
            if best == nil,
               let scrollView = view as? UIScrollView,
               scrollView.isScrollEnabled,
               scrollView.contentSize.height > scrollView.bounds.height + 1
                || scrollView.contentSize.width > scrollView.bounds.width + 1 {
                best = scrollView
            }
        }
        visit(root)
        return best
    }

    private func frontmostWebView(in root: UIView) -> WKWebView? {
        var best: WKWebView?
        func visit(_ view: UIView) {
            guard best == nil, !view.isHidden, view.alpha > 0.01 else { return }
            for subview in view.subviews.reversed() {
                visit(subview)
            }
            if best == nil, let webView = view as? WKWebView {
                best = webView
            }
        }
        visit(root)
        return best
    }

    /// Last-resort fallback: ask the window's accessibility tree to page in
    /// the scroll direction. This is the `accessibilityScroll(_:)` action —
    /// strictly in-process, it cannot reach other apps. Small deltas are
    /// ignored because this action pages a full screen at a time.
    private func postAccessibilityScroll(dy: CGFloat, in window: UIWindow) {
        guard abs(dy) > 20 else { return }
        let direction: UIAccessibilityScrollDirection = dy > 0 ? .down : .up
        if window.accessibilityScroll(direction) {
            // Announce the page change to VoiceOver users, mirroring what a
            // native paging control would do.
            UIAccessibility.post(notification: .pageScrolled, argument: nil)
        }
    }
}
