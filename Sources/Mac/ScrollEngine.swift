import Foundation
import ScrollCore

/// Runs the momentum simulation at 120 Hz while there is something to scroll
/// and sleeps otherwise.
final class ScrollEngine {
    private let queue = DispatchQueue(label: "dev.doomscroll.engine", qos: .userInteractive)
    private let injector = ScrollInjector()
    private var scroller = MomentumScroller()
    private var timer: DispatchSourceTimer?
    private var lastTick: TimeInterval = 0
    private var target: ScrollTarget = .pointer

    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func setTarget(_ target: ScrollTarget) {
        queue.async { self.target = target }
    }

    func continuous(dx: Int, dy: Int) {
        queue.async {
            self.scroller.setContinuous(dx: Double(dx), dy: Double(dy), at: self.now())
            self.ensureTimer()
        }
    }

    func fling(vx: Int, vy: Int) {
        queue.async {
            self.scroller.fling(vx: Double(vx), vy: Double(vy))
            self.ensureTimer()
        }
    }

    /// Applies a scroll distance (points) right away, as the Digital Crown sends.
    func nudge(dx: Int, dy: Int) {
        queue.async {
            self.scroller.nudge(dx: Double(dx), dy: Double(dy))
            self.ensureTimer()
        }
    }

    /// Double-clicks where scrolling lands, which likes the post in most feeds
    /// (and is a double tap on the iPhone when aimed at iPhone Mirroring).
    func like() {
        queue.async {
            let point = TargetResolver.point(for: self.target)
            self.injector.doubleClick(at: point)
        }
    }

    func stopAll() {
        queue.async {
            self.scroller.stop()
            self.cancelTimer()
        }
    }

    /// Ends continuous scrolling but lets any fling coast to a stop.
    func releaseContinuous() {
        queue.async { self.scroller.setContinuous(dx: 0, dy: 0, at: self.now()) }
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        lastTick = now()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let t = now()
        let dt = min(0.05, max(0.001, t - lastTick))
        lastTick = t
        let d = scroller.tick(dt: dt, at: t)
        if d.dx != 0 || d.dy != 0 {
            injector.scroll(dx: d.dx, dy: d.dy, at: TargetResolver.point(for: target))
        }
        if scroller.isIdle { cancelTimer() }
    }
}
