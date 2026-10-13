import Foundation
import Testing
@testable import ScrollCore

private let key = Data(repeating: 7, count: 32)

@Suite struct WireProtocolTests {
    @Test func sealOpenRoundTripThroughJSON() throws {
        let auth = MessageAuthenticator(key: key)
        let env = auth.seal(.fling(vx: -1200, vy: 3400), seq: 5, nowMs: 1_000)
        let decoded = try JSONDecoder().decode(Envelope.self, from: JSONEncoder().encode(env))
        #expect(try auth.open(decoded) == .fling(vx: -1200, vy: 3400))
    }

    @Test func tamperedPayloadIsRejected() {
        let auth = MessageAuthenticator(key: key)
        var env = auth.seal(.scroll(dx: 10, dy: 20), seq: 1, nowMs: 1)
        env.b = 9999
        #expect(throws: WireError.badMAC) { try auth.open(env) }
    }

    @Test func wrongKeyIsRejected() {
        let env = MessageAuthenticator(key: key).seal(.ping, seq: 1, nowMs: 1)
        let other = MessageAuthenticator(key: Data(repeating: 8, count: 32))
        #expect(throws: WireError.badMAC) { try other.open(env) }
    }

    @Test func modeMessageCarriesTarget() throws {
        let auth = MessageAuthenticator(key: key)
        let env = auth.seal(.mode(active: true, target: .iPhoneMirroring), seq: 2, nowMs: 2)
        #expect(try auth.open(env) == .mode(active: true, target: .iPhoneMirroring))
    }

    @Test func replayAndStaleAreRejected() throws {
        let auth = MessageAuthenticator(key: key)
        var replay = ReplayGuard(maxSkewMs: 1_000)
        let e1 = auth.seal(.ping, seq: 1, nowMs: 10_000)
        try replay.check(e1, nowMs: 10_100)
        #expect(throws: WireError.replayed) { try replay.check(e1, nowMs: 10_200) }
        let old = auth.seal(.ping, seq: 2, nowMs: 1_000)
        #expect(throws: WireError.stale) { try replay.check(old, nowMs: 10_300) }
    }

    @Test func pairingTokenRoundTrip() {
        let token = PairingToken.generate(macName: "Jacob's MacBook Pro")
        #expect(PairingToken(urlString: token.urlString) == token)
        #expect(token.key.count == 32)
    }

    @Test func pairingTokenRejectsGarbage() {
        #expect(PairingToken(urlString: "https://example.com") == nil)
        #expect(PairingToken(urlString: "doomscroll://pair?k=AAAA") == nil)
    }
}

@Suite struct WristMotionTests {
    private func sample(_ t: Double, pitch: Double = 0, roll: Double = 0,
                        pr: Double = 0, rr: Double = 0) -> MotionSample {
        MotionSample(t: t, pitch: pitch, roll: roll, pitchRate: pr, rollRate: rr)
    }

    private func tiltProcessor(invertY: Bool = false) -> WristMotionProcessor {
        var cfg = ProcessorConfig()
        cfg.style = .tilt
        cfg.invertY = invertY
        let p = WristMotionProcessor(config: cfg)
        p.begin(neutralPitch: 0, neutralRoll: 0)
        return p
    }

    @Test func tiltInsideDeadzoneEmitsNothing() {
        #expect(tiltProcessor().process(sample(0, pitch: 0.05)).isEmpty)
    }

    @Test func tiltScalesAndStopsWithSingleZero() {
        let p = tiltProcessor()
        guard case let .scroll(_, small)? = p.process(sample(0, pitch: 0.3)).first,
              case let .scroll(_, big)? = p.process(sample(0.02, pitch: 0.6)).first
        else { Issue.record("expected scroll outputs"); return }
        #expect(small > 0)
        #expect(big > small)
        #expect(big <= Int(ProcessorConfig().maxTiltVelocity))
        #expect(p.process(sample(0.04, pitch: 0)) == [.scroll(dx: 0, dy: 0)])
        #expect(p.process(sample(0.06, pitch: 0)).isEmpty)
    }

    @Test func tiltIsRelativeToNeutralPose() {
        var cfg = ProcessorConfig()
        cfg.style = .tilt
        let p = WristMotionProcessor(config: cfg)
        p.begin(neutralPitch: 0.8, neutralRoll: 0)
        #expect(p.process(sample(0, pitch: 0.85)).isEmpty)
    }

    @Test func invertFlipsDirection() {
        let p = tiltProcessor(invertY: true)
        guard case let .scroll(_, dy)? = p.process(sample(0, pitch: 0.5)).first else {
            Issue.record("expected scroll"); return
        }
        #expect(dy < 0)
    }

    /// Outward stroke peaking at 6 rad/s over ~0.1 s, then the return stroke.
    private func snap(sign: Double, axis: WritableKeyPath<MotionSample, Double>) -> [MotionSample] {
        var out: [MotionSample] = []
        var t = 0.0
        for r in [1.0, 4.0, 6.0, 5.0, 2.5, 0.5, -2.0, -4.0, -3.0, -1.0, 0.0] {
            var s = MotionSample(t: t, pitch: 0, roll: 0, pitchRate: 0, rollRate: 0)
            s[keyPath: axis] = sign * r
            out.append(s)
            t += 0.02
        }
        return out
    }

    @Test func flickProducesOneFlingAndIgnoresReturnStroke() {
        let p = WristMotionProcessor()
        p.begin(neutralPitch: 0, neutralRoll: 0)
        let outputs = snap(sign: 1, axis: \.pitchRate).flatMap { p.process($0) }
        #expect(outputs.count == 1)
        guard case let .fling(vx, vy)? = outputs.first else { Issue.record("no fling"); return }
        #expect(vx == 0)
        #expect(vy > 2000)
    }

    @Test func negativeFlickGoesTheOtherWay() {
        let p = WristMotionProcessor()
        p.begin(neutralPitch: 0, neutralRoll: 0)
        let outputs = snap(sign: -1, axis: \.pitchRate).flatMap { p.process($0) }
        guard case let .fling(_, vy)? = outputs.first else { Issue.record("no fling"); return }
        #expect(vy < 0)
    }

    @Test func rollFlickMapsToHorizontal() {
        let p = WristMotionProcessor()
        p.begin(neutralPitch: 0, neutralRoll: 0)
        let outputs = snap(sign: 1, axis: \.rollRate).flatMap { p.process($0) }
        guard case let .fling(vx, vy)? = outputs.first else { Issue.record("no fling"); return }
        #expect(vx > 0)
        #expect(vy == 0)
    }

    @Test func slowDeliberateRotationIsNotAFlick() {
        let p = WristMotionProcessor()
        p.begin(neutralPitch: 0, neutralRoll: 0)
        var outputs: [ProcessorOutput] = []
        var t = 0.0
        for _ in 0..<40 {
            outputs += p.process(sample(t, pr: 3.2))
            t += 0.02
        }
        #expect(outputs.isEmpty)
    }

    @Test func smallJitterIsNotAFlick() {
        let p = WristMotionProcessor()
        p.begin(neutralPitch: 0, neutralRoll: 0)
        var outputs: [ProcessorOutput] = []
        var t = 0.0
        for r in [0.2, 0.8, 1.5, 0.9, 0.1, -0.5, -1.1, -0.3] {
            outputs += p.process(sample(t, pr: r))
            t += 0.02
        }
        #expect(outputs.isEmpty)
    }
}

@Suite struct MomentumTests {
    @Test func flingCoastsThenStops() {
        var m = MomentumScroller()
        m.fling(vx: 0, vy: 4000)
        var total = 0
        var t = 0.0
        var previous = 1_000_000
        for _ in 0..<400 {
            t += 0.01
            let d = m.tick(dt: 0.01, at: t)
            total += d.dy
            #expect(d.dy <= previous + 1)
            previous = d.dy
        }
        #expect(m.isIdle)
        #expect(abs(Double(total) - 1800) < 120)   // integral of v0*exp(-t/tau) = v0*tau
    }

    @Test func continuousTimesOutWhenLinkDrops() {
        var m = MomentumScroller()
        m.setContinuous(dx: 0, dy: 1000, at: 0)
        #expect(m.tick(dt: 0.01, at: 0.05).dy > 0)
        #expect(m.tick(dt: 0.01, at: 1.0).dy == 0)
    }

    @Test func fractionalMotionAccumulates() {
        var m = MomentumScroller()
        m.setContinuous(dx: 0, dy: 30, at: 0)
        var total = 0
        for i in 1...100 { total += m.tick(dt: 0.01, at: Double(i) * 0.002).dy }
        #expect(abs(total - 30) <= 1)
    }

    @Test func stopClearsEverything() {
        var m = MomentumScroller()
        m.fling(vx: 5000, vy: 5000)
        m.stop()
        #expect(m.isIdle)
        let d = m.tick(dt: 0.01, at: 0.01)
        #expect(d.dx == 0 && d.dy == 0)
    }
}

@Suite struct FramerTests {
    @Test func splitsMultipleLinesAndHandlesPartialReads() throws {
        var f = LineFramer()
        #expect(try f.push(Data("{\"a\":1}\n{\"b\"".utf8)) == [Data("{\"a\":1}".utf8)])
        #expect(try f.push(Data(":2}\n\n".utf8)) == [Data("{\"b\":2}".utf8)])
    }

    @Test func oversizedLineThrowsAndRecovers() throws {
        var f = LineFramer()
        #expect(throws: LineFramer.FramingError.lineTooLong) {
            try f.push(Data(repeating: 0x41, count: LineFramer.maxLineBytes + 10))
        }
        #expect(try f.push(Data("ok\n".utf8)) == [Data("ok".utf8)])
    }

    @Test func envelopeEncodesToSingleLine() throws {
        let env = MessageAuthenticator(key: key).seal(.ping, seq: 1, nowMs: 1)
        let data = try LineFramer.encode(env)
        #expect(data.last == 0x0A)
        #expect(data.dropLast().contains(0x0A) == false)
        var f = LineFramer()
        let lines = try f.push(data)
        #expect(try JSONDecoder().decode(Envelope.self, from: lines[0]) == env)
    }
}

@Suite struct SettingsAndSyncTests {
    @Test func settingsRoundTripAsJSON() throws {
        var s = ScrollSettings()
        s.style = .tilt; s.sensitivity = 1.7; s.invertY = true; s.target = .iPhoneMirroring
        let back = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func sensitivityIsClamped() {
        var s = ScrollSettings()
        s.sensitivity = 99
        #expect(s.processorConfig.sensitivity == ScrollSettings.sensitivityRange.upperBound)
        s.sensitivity = -3
        #expect(s.processorConfig.sensitivity == ScrollSettings.sensitivityRange.lowerBound)
    }

    @Test func watchConnectivityDictionaryRoundTrip() {
        let messages: [WireMessage] = [.scroll(dx: -5, dy: 900), .fling(vx: 10, vy: -4000),
                                       .mode(active: true, target: .iPhoneMirroring), .ping]
        for m in messages { #expect(WCKey.message(from: WCKey.dictionary(for: m)) == m) }
        #expect(WCKey.message(from: ["t": "scroll"]) == nil)
        #expect(WCKey.message(from: ["t": "bogus", "a": 1, "b": 2]) == nil)
    }
}

#if canImport(Network)
import Network

@Suite struct ServerIntegrationTests {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        private var messages: [WireMessage] = []
        func add(_ m: WireMessage) { lock.lock(); messages.append(m); lock.unlock() }
        var all: [WireMessage] { lock.lock(); defer { lock.unlock() }; return messages }
    }

    /// Real TCP round trip on loopback: only authenticated, fresh, in-order
    /// messages may reach the callback.
    @Test func onlyAuthenticFreshMessagesAreDelivered() async throws {
        let box = Box()
        let server = ScrollServer(key: key, serviceName: "test", advertise: false, callbacks: .init(
            onMessage: { box.add($0) }, onClientCountChanged: { _ in }, onListenerState: { _ in }))
        server.start()
        defer { server.stop() }

        var port: UInt16 = 0
        for _ in 0..<100 {
            if let p = server.port, p != 0 { port = p; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try #require(port != 0)

        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        conn.start(queue: .global())
        defer { conn.cancel() }
        try await Task.sleep(nanoseconds: 300_000_000)

        func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
        func send(_ env: Envelope) async throws {
            conn.send(content: try LineFramer.encode(env), completion: .idempotent)
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        let auth = MessageAuthenticator(key: key)
        try await send(auth.seal(.mode(active: true, target: .iPhoneMirroring), seq: 1, nowMs: nowMs()))
        try await send(auth.seal(.scroll(dx: 10, dy: 700), seq: 2, nowMs: nowMs()))
        try await send(auth.seal(.scroll(dx: 10, dy: 700), seq: 2, nowMs: nowMs()))          // replay
        var tampered = auth.seal(.fling(vx: 0, vy: 5000), seq: 3, nowMs: nowMs())
        tampered.b = 9000
        try await send(tampered)                                                             // bad MAC
        try await send(MessageAuthenticator(key: Data(repeating: 1, count: 32))
            .seal(.fling(vx: 0, vy: 5000), seq: 4, nowMs: nowMs()))                          // wrong key
        try await send(auth.seal(.ping, seq: 5, nowMs: nowMs() - 120_000))                   // stale
        try await send(auth.seal(.fling(vx: -300, vy: 4200), seq: 6, nowMs: nowMs()))
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(box.all == [.mode(active: true, target: .iPhoneMirroring),
                            .scroll(dx: 10, dy: 700),
                            .fling(vx: -300, vy: 4200)])
    }
}
#endif

@Suite struct CalibrationTests {
    /// A 0.12 s snap on one axis; `sign` picks the direction.
    private func snap(sign: Double, vertical: Bool, from start: Double = 0) -> [MotionSample] {
        var out: [MotionSample] = []
        var t = start
        for r in [1.0, 4.0, 6.0, 5.0, 2.5, 0.5, -2.0, -4.0, -3.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] {
            out.append(MotionSample(t: t, pitch: 0, roll: 0,
                                    pitchRate: vertical ? sign * r : 0,
                                    rollRate: vertical ? 0 : sign * r))
            t += 0.02
        }
        return out
    }

    private func run(_ session: CalibrationSession, _ samples: [MotionSample]) -> [CalibrationSession.Outcome] {
        samples.map { session.process($0) }.filter { $0 != .none }
    }

    @Test func positiveFlicksMeanNoInversion() {
        let s = CalibrationSession()
        #expect(run(s, snap(sign: 1, vertical: true)) == [.accepted(.down)])
        #expect(s.step == .right)
        #expect(run(s, snap(sign: 1, vertical: false, from: 2)) == [.finished(invertX: false, invertY: false, swapAxes: false)])
        #expect(s.isFinished)
    }

    @Test func negativeFlicksMeanInversion() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: -1, vertical: true))
        #expect(run(s, snap(sign: -1, vertical: false, from: 2)) == [.finished(invertX: true, invertY: true, swapAxes: false)])
    }

    @Test func eachAxisIsLearnedIndependently() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: 1, vertical: true))
        #expect(run(s, snap(sign: -1, vertical: false, from: 2)) == [.finished(invertX: true, invertY: false, swapAxes: false)])
    }

    @Test func aSidewaysFlickIsAcceptedForTheFirstStep() {
        let s = CalibrationSession()
        #expect(run(s, snap(sign: 1, vertical: false)) == [.accepted(.down)])
        #expect(s.step == .right)
    }

    @Test func sidewaysThenVerticalSwapsTheAxes() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: -1, vertical: false))
        #expect(run(s, snap(sign: 1, vertical: true, from: 2))
                == [.finished(invertX: false, invertY: true, swapAxes: true)])
    }

    @Test func theSameKindOfFlickTwiceIsTheOnlyInvalidCase() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: 1, vertical: true))
        // Same axis again, even in the other direction: invalid, still on step 2.
        #expect(run(s, snap(sign: -1, vertical: true, from: 2)) == [.sameMotion(expected: .right)])
        #expect(s.step == .right)
        // A different kind of flick then completes it.
        #expect(run(s, snap(sign: 1, vertical: false, from: 4))
                == [.finished(invertX: false, invertY: false, swapAxes: false)])
    }

    @Test func sidewaysTwiceIsAlsoInvalid() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: 1, vertical: false))
        #expect(run(s, snap(sign: 1, vertical: false, from: 2)) == [.sameMotion(expected: .right)])
    }

    @Test func swappedAxesDriveTheScrollDirections() {
        var c = ProcessorConfig()
        c.swapAxes = true
        let p = WristMotionProcessor(config: c)
        p.begin(neutralPitch: 0, neutralRoll: 0)
        var out: [ProcessorOutput] = []
        var t = 0.0
        // A roll (sideways) snap now scrolls vertically.
        for r in [1.0, 4.0, 6.0, 5.0, 2.5, 0.5, -2.0, -4.0, -3.0, -1.0, 0.0] {
            out += p.process(MotionSample(t: t, pitch: 0, roll: 0, pitchRate: 0, rollRate: r))
            t += 0.02
        }
        #expect(out.contains { if case let .fling(vx, vy) = $0 { return vx == 0 && vy > 0 } else { return false } })
    }

    @Test func connectionModeDefaultsToAutomaticAndSurvivesJSON() throws {
        #expect(ScrollSettings().connection == .automatic)
        let old = #"{"style":"flick"}"#
        #expect(try JSONDecoder().decode(ScrollSettings.self, from: Data(old.utf8)).connection == .automatic)
        var s = ScrollSettings(); s.connection = .bluetooth
        #expect(try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s)).connection == .bluetooth)
    }

    @Test func swapAxesDefaultsOffAndOldSettingsLoad() throws {
        #expect(!ScrollSettings().swapAxes && !ScrollSettings().phoneSwapAxes)
        let old = #"{"style":"flick","sensitivity":1.5}"#
        let back = try JSONDecoder().decode(ScrollSettings.self, from: Data(old.utf8))
        #expect(!back.swapAxes && !back.phoneSwapAxes)
        var s = ScrollSettings(); s.swapAxes = true; s.phoneSwapAxes = true
        #expect(s.processorConfig.swapAxes && s.phoneProcessorConfig.swapAxes)
    }

    @Test func restartForgetsEverything() {
        let s = CalibrationSession()
        _ = run(s, snap(sign: -1, vertical: true))
        s.restart()
        #expect(s.step == .down)
        _ = run(s, snap(sign: 1, vertical: true, from: 3))
        #expect(run(s, snap(sign: 1, vertical: false, from: 6)) == [.finished(invertX: false, invertY: false, swapAxes: false)])
    }
}

@Suite struct ControlMessageTests {
    @Test func calibrationResultRoundTrips() {
        let m = ControlMessage.calibrationResult(invertX: true, invertY: false, swapAxes: true)
        #expect(ControlMessage(dictionary: m.dictionary) == m)
        // Older builds send no swap flag.
        #expect(ControlMessage(dictionary: ["t": "cal_result", "a": 1, "b": 0])
                == .calibrationResult(invertX: true, invertY: false, swapAxes: false))
        #expect(ControlMessage(dictionary: ["t": "nope", "a": 1, "b": 1]) == nil)
        #expect(ControlMessage(dictionary: ["t": "cal_result"]) == nil)
    }

    @Test func calibratedFlagSurvivesJSON() throws {
        var s = ScrollSettings()
        s.calibrated = true
        let back = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s))
        #expect(back.calibrated)
    }
}

@Suite struct PhoneGestureTests {
    private func snap(sign: Double) -> [MotionSample] {
        var out: [MotionSample] = []
        var t = 0.0
        for r in [1.0, 4.0, 6.0, 5.0, 2.5, 0.5, -2.0, -4.0, -3.0, -1.0, 0.0] {
            out.append(MotionSample(t: t, pitch: 0, roll: 0, pitchRate: sign * r, rollRate: 0))
            t += 0.02
        }
        return out
    }

    @Test func phoneStyleFlicksLikeTheFlickStyle() {
        var cfg = ProcessorConfig()
        cfg.style = .phone
        let p = WristMotionProcessor(config: cfg)
        p.begin(neutralPitch: 0, neutralRoll: 0)
        let outputs = snap(sign: 1).flatMap { p.process($0) }
        #expect(outputs.count == 1)
        guard case let .fling(_, vy)? = outputs.first else { Issue.record("no fling"); return }
        #expect(vy > 2000)
    }

    @Test func phoneConfigUsesItsOwnSignsAndAlwaysFlicks() {
        var s = ScrollSettings()
        s.style = .tilt; s.invertY = false; s.phoneInvertY = true
        let cfg = s.phoneProcessorConfig
        #expect(cfg.style == .flick)
        #expect(cfg.invertY)
        #expect(!s.processorConfig.invertY)
    }

    @Test func settingsFromAnOlderBuildStillLoad() throws {
        let old = #"{"style":"tilt","sensitivity":1.4,"invertX":true,"invertY":false,"target":1,"hapticsEnabled":false}"#
        let s = try JSONDecoder().decode(ScrollSettings.self, from: Data(old.utf8))
        #expect(s.style == .tilt)
        #expect(s.sensitivity == 1.4)
        #expect(s.invertX)
        #expect(s.target == .iPhoneMirroring)
        #expect(!s.hapticsEnabled)
        #expect(!s.calibrated && !s.phoneCalibrated && !s.phoneInvertX)
    }

    @Test func phoneSettingsRoundTrip() throws {
        var s = ScrollSettings()
        s.style = .phone; s.phoneInvertX = true; s.phoneCalibrated = true
        let back = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.style == .phone)
    }
}

@Suite struct DestinationTests {
    @Test func defaultsToMac() {
        #expect(ScrollSettings().destination == .mac)
    }

    @Test func phoneDestinationSurvivesJSON() throws {
        var s = ScrollSettings()
        s.destination = .phone
        let back = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s))
        #expect(back.destination == .phone)
    }

    @Test func settingsFromABuildWithoutDestinationStillLoad() throws {
        let old = #"{"style":"flick","sensitivity":1.5}"#
        let s = try JSONDecoder().decode(ScrollSettings.self, from: Data(old.utf8))
        #expect(s.destination == .mac)
        #expect(s.sensitivity == 1.5)
    }
}

@Suite struct CrownTests {
    @Test func firstTurnSendsItsDistanceImmediately() {
        var c = CrownScroller()
        #expect(c.rotate(by: 0.1, at: 0, sensitivity: 1, reversed: false) == .nudge(dx: 0, dy: 25))
    }

    @Test func turnsInsideTheIntervalAreSummedNotLost() {
        var c = CrownScroller()
        _ = c.rotate(by: 0.1, at: 0, sensitivity: 1, reversed: false)
        #expect(c.rotate(by: 0.1, at: 0.01, sensitivity: 1, reversed: false) == nil)
        #expect(c.rotate(by: 0.1, at: 0.04, sensitivity: 1, reversed: false) == .nudge(dx: 0, dy: 50))
    }

    @Test func reversedAndSensitivityApply() {
        var a = CrownScroller()
        #expect(a.rotate(by: 0.1, at: 0, sensitivity: 1, reversed: true) == .nudge(dx: 0, dy: -25))
        var b = CrownScroller()
        #expect(b.rotate(by: 0.1, at: 0, sensitivity: 2, reversed: false) == .nudge(dx: 0, dy: 50))
    }

    @Test func distancePerMessageIsCapped() {
        var c = CrownScroller()
        #expect(c.rotate(by: 100, at: 0, sensitivity: 1, reversed: false) == .nudge(dx: 0, dy: 600))
    }

    @Test func idleFlushesWhateverIsStillWaiting() {
        var c = CrownScroller()
        _ = c.rotate(by: 0.1, at: 0, sensitivity: 1, reversed: false)
        #expect(c.rotate(by: 0.2, at: 0.01, sensitivity: 1, reversed: false) == nil)
        #expect(c.idle() == .nudge(dx: 0, dy: 50))
        #expect(c.idle() == nil)
    }

    @Test func aTinyLeftoverIsDroppedWhenTheCrownStops() {
        var c = CrownScroller()
        #expect(c.rotate(by: 0.001, at: 0, sensitivity: 1, reversed: false) == nil)
        #expect(c.idle() == nil)
        #expect(c.rotate(by: 0.1, at: 1, sensitivity: 1, reversed: false) == .nudge(dx: 0, dy: 25))
    }

    @Test func nudgeSurvivesTheWireAndTheWatchRelay() throws {
        let auth = MessageAuthenticator(key: Data(repeating: 7, count: 32))
        let env = auth.seal(.nudge(dx: 0, dy: -40), seq: 1, nowMs: 1_000)
        #expect(try auth.open(env) == .nudge(dx: 0, dy: -40))
        #expect(WCKey.message(from: WCKey.dictionary(for: .nudge(dx: 3, dy: 25))) == .nudge(dx: 3, dy: 25))
    }

    @Test func macAppliesANudgeFullyAndThenStopsAtOnce() {
        var m = MomentumScroller()
        m.nudge(dx: 0, dy: 100)
        #expect(!m.isIdle)
        var total = 0
        var firstTick = 0
        for i in 0..<120 {
            let d = m.tick(dt: 1.0 / 120, at: Double(i) / 120)
            if i == 0 { firstTick = d.dy }
            total += d.dy
        }
        // Whole pixels only: under one point stays in the sub-pixel remainder.
        #expect(abs(total - 100) <= 1)
        #expect(firstTick > 0)
        #expect(m.isIdle)
    }

    @Test func nudgeDoesNotKeepScrollingAfterItsDistanceIsUsed() {
        var m = MomentumScroller()
        m.nudge(dx: 0, dy: -60)
        var total = 0
        for i in 0..<240 { total += m.tick(dt: 1.0 / 120, at: Double(i) / 120).dy }
        #expect(abs(total + 60) <= 1)
        #expect(m.tick(dt: 1.0 / 120, at: 3).dy == 0)
    }

    @Test func crownSettingDefaultsOffAndSurvivesJSON() throws {
        #expect(ScrollSettings().crownReversed == false)
        var s = ScrollSettings()
        s.crownReversed = true
        let back = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(s))
        #expect(back.crownReversed)
    }
}

@Suite struct LikeAndBluetoothTests {
    @Test func likeSurvivesTheWireAndTheWatchRelay() throws {
        let auth = MessageAuthenticator(key: Data(repeating: 9, count: 32))
        #expect(try auth.open(auth.seal(.like, seq: 1, nowMs: 1_000)) == .like)
        #expect(WCKey.message(from: WCKey.dictionary(for: .like)) == .like)
    }

    @Test func likeDoesNotMoveAReel() {
        var p = PageStepper()
        #expect(p.handle(.like, at: 0) == 0)
    }

    @Test func bluetoothNameMatchToleratesShortenedNames() {
        let expected = BluetoothTransport.advertisedName(for: "MacBook Pro von Jacob")
        #expect(BluetoothTransport.nameMatches(advertised: expected, expected: expected))
        #expect(BluetoothTransport.nameMatches(advertised: "MacBook Pro v", expected: expected))
        #expect(!BluetoothTransport.nameMatches(advertised: "Someone's iMac", expected: expected))
        #expect(!BluetoothTransport.nameMatches(advertised: "", expected: expected))
    }
}

@Suite struct PageStepperTests {
    @Test func aFlickStepsOnceAndTheCooldownBlocksTheNext() {
        var p = PageStepper()
        #expect(p.handle(.fling(vx: 0, vy: 1500), at: 0) == 1)
        #expect(p.handle(.fling(vx: 0, vy: 1500), at: 0.2) == 0)
        #expect(p.handle(.fling(vx: 0, vy: -1500), at: 0.6) == -1)
    }

    @Test func crownNudgesStepOnceEnoughDistanceBuilds() {
        var p = PageStepper()
        #expect(p.handle(.nudge(dx: 0, dy: 100), at: 0) == 0)
        #expect(p.handle(.nudge(dx: 0, dy: 100), at: 0.03) == 1)
        #expect(p.handle(.nudge(dx: 0, dy: 100), at: 0.1) == 0)
        #expect(p.handle(.nudge(dx: 0, dy: -200), at: 0.7) == -1)
    }

    @Test func weakAndSidewaysFlicksAreIgnored() {
        var p = PageStepper()
        #expect(p.handle(.fling(vx: 0, vy: 200), at: 0) == 0)
        #expect(p.handle(.fling(vx: 2000, vy: 800), at: 1) == 0)
    }

    @Test func continuousInputStepsOnceEnoughDistanceBuilds() {
        var p = PageStepper()
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0) == 0)
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0.05) == 0)
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0.10) == 0)
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0.15) == 1)
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0.20) == 0)
    }

    @Test func continuousUpwardInputStepsBack() {
        var p = PageStepper()
        var step = 0
        for i in 0..<5 where step == 0 {
            step = p.handle(.scroll(dx: 0, dy: -1000), at: Double(i) * 0.05)
        }
        #expect(step == -1)
    }

    @Test func stopResetsTheBuiltUpDistance() {
        var p = PageStepper()
        _ = p.handle(.scroll(dx: 0, dy: 1000), at: 0)
        _ = p.handle(.scroll(dx: 0, dy: 1000), at: 0.05)
        _ = p.handle(.scroll(dx: 0, dy: 1000), at: 0.10)
        _ = p.handle(.scroll(dx: 0, dy: 0), at: 0.12)
        #expect(p.handle(.scroll(dx: 0, dy: 1000), at: 0.17) == 0)
    }

    @Test func reelsModeDefaultsOnAndOldSettingsLoad() throws {
        #expect(ScrollSettings().reelsMode)
        let s = try JSONDecoder().decode(ScrollSettings.self, from: Data(#"{"style":"tilt"}"#.utf8))
        #expect(s.reelsMode)
    }
}
