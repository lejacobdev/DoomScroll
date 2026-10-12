import QuartzCore
import ScrollCore
import UIKit

/// Scrolls the DoomScroll browser on this iPhone from Watch commands, with the
/// same momentum physics the Mac helper uses. This is the "no Mac" path.
///
/// iOS has no public way for one app to scroll another, so this only drives a
/// scroll view inside DoomScroll. It does not reach Safari or other apps.
@MainActor
final class PhoneScroller: ObservableObject {
    static let shared = PhoneScroller()

    /// True between the Watch turning scroll mode on and off.
    @Published private(set) var watchActive = false

    private weak var scrollView: UIScrollView?
    private var scroller = MomentumScroller()
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?
    private var lastTick: TimeInterval = 0

    func attach(_ view: UIScrollView) {
        scrollView = view
    }

    func detach(_ view: UIScrollView) {
        guard scrollView === view else { return }
        scrollView = nil
        scroller.stop()
        stopLink()
        watchActive = false
    }

    func handle(_ message: WireMessage) {
        let now = ProcessInfo.processInfo.systemUptime
        switch message {
        case let .scroll(dx, dy):
            scroller.setContinuous(dx: Double(dx), dy: Double(dy), at: now)
            startLinkIfNeeded()
        case let .fling(vx, vy):
            scroller.fling(vx: Double(vx), vy: Double(vy))
            startLinkIfNeeded()
        case let .mode(active, _):
            watchActive = active
            // Release a held tilt but let a fling coast to a stop.
            if !active { scroller.setContinuous(dx: 0, dy: 0, at: now) }
        case .ping:
            break
        }
    }

    // MARK: Animation

    private func startLinkIfNeeded() {
        guard displayLink == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let proxy = DisplayLinkProxy { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    private func tick() {
        guard let view = scrollView else {
            scroller.stop()
            stopLink()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, now - lastTick))
        lastTick = now
        let delta = scroller.tick(dt: dt, at: now)
        if delta.dx != 0 || delta.dy != 0 {
            move(view, dx: CGFloat(delta.dx), dy: CGFloat(delta.dy))
        }
        if scroller.isIdle { stopLink() }
    }

    /// Positive `dy` reveals content below, positive `dx` reveals content to the
    /// right, matching the Mac helper. Clamped so it never overscrolls.
    private func move(_ view: UIScrollView, dx: CGFloat, dy: CGFloat) {
        let inset = view.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, view.contentSize.width + inset.right - view.bounds.width)
        let maxY = max(minY, view.contentSize.height + inset.bottom - view.bounds.height)
        var offset = view.contentOffset
        offset.x = min(max(offset.x + dx, minX), maxX)
        offset.y = min(max(offset.y + dy, minY), maxY)
        if offset != view.contentOffset {
            view.setContentOffset(offset, animated: false)
        }
    }
}

/// CADisplayLink retains its target, so a small proxy keeps the scroller from
/// being retained by the run loop.
private final class DisplayLinkProxy: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}

/// Entry point for the WatchConnectivity queue, which is not the main thread.
enum PhoneScrollSink {
    static func deliver(_ message: WireMessage) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { PhoneScroller.shared.handle(message) }
        }
    }
}
