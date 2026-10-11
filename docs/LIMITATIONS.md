# What this actually does, and what it can't

## System-wide scroll, by platform

| Target | Works? | How |
|---|---|---|
| **Mac, any app** | Yes | The Mac helper posts real `CGEvent` scroll-wheel events via `CGEvent.post(tap: .cghidEventTap)`. This reaches every app once you grant Accessibility access — it's the same mechanism a real mouse or trackpad uses, not a hack specific to one app. |
| **iPhone, via Mac + iPhone Mirroring** | Yes, indirectly | macOS's iPhone Mirroring feature renders your iPhone's screen in a Mac window and forwards input to it. The Mac helper finds that window (`CGWindowListCopyWindowInfo`) and posts scroll events into its center point. This scrolls whatever's on your iPhone screen, in any app — but only while iPhone Mirroring is open, and only while the Mac is nearby. |
| **iPhone directly, any app, no Mac** | **No — not possible on stock iOS** | iOS's app sandbox gives a third-party app zero access to another process's UI. There is no public API for one app to scroll another. `AXUIElement` (what makes this possible on macOS) doesn't exist on iOS. `UIAccessibility` actions are strictly in-process. IOKit/HID event injection is private API; apps using it are rejected from the App Store and from TestFlight review. This is a sandboxing boundary, not a missing feature — no amount of entitlements or paid developer account changes it. |

If you want hands-free scrolling with no Mac involved, in the current state
of iOS that is not achievable with code that can be distributed through
TestFlight or the App Store. The Mac + iPhone Mirroring path is the closest
real equivalent — same "scroll my phone without touching it" outcome, with
the Mac doing the part iOS refuses to let an app do.

## Gesture

- **watchOS 11+ (Series 9, Ultra 2, and later):** the system **Double Tap**
  gesture is wired via `.handGestureShortcut(.primaryAction)`. This is
  Apple's real hardware gesture — the same one used for answering calls —
  not an approximation.
- **watchOS 10 (no system Double Tap):** `DoubleTapDetector` falls back to
  reading raw accelerometer peaks and recognizing two taps in quick
  succession. Less reliable than the system gesture, especially with the
  wrist in motion; tune `tapThreshold`/`minInterval`/`maxInterval` in
  `Sources/Watch/DoubleTapDetector.swift` if it's over- or under-firing.
- No touch is used anywhere in the control loop once scroll mode is active —
  wrist motion alone drives scrolling, per your request.

## Control feel

Two styles, switchable in the iPhone app's Settings:

- **Flick** (default): snap your wrist like flicking a page; the content
  coasts and decelerates, like a real trackpad fling. A slow, deliberate
  rotation is deliberately *not* recognized as a flick (see
  `WristMotionProcessor.swift` — `flickMaxDuration`), so resting your wrist
  tilted doesn't accidentally fire one.
- **Tilt**: hold your wrist tilted to scroll continuously, like a joystick;
  return to neutral to stop. Has a deadzone so a relaxed wrist doesn't drift.

Both run entirely from `CMDeviceMotion.attitude`/`rotationRate` — pitch
drives vertical scroll, roll drives horizontal, yaw is ignored so turning
your head or torso while wearing the watch doesn't inject noise.

## Reliability details worth knowing

- **Link priority:** the Watch prefers talking to the Mac directly over Wi-Fi
  (Bonjour discovery + a persistent TCP connection). If it can't find the
  Mac, it relays through the iPhone over WatchConnectivity instead — slightly
  higher latency, but it keeps working if the Watch and Mac are briefly on
  different networks while the iPhone bridges both.
- **Authentication:** every message is HMAC-SHA256 signed with a key
  established once by scanning a QR code shown in the Mac app. An
  unauthenticated device on the same Wi-Fi network cannot send scroll
  commands — the server verifies the MAC before accepting anything.
- **Replay/staleness:** messages carry a sequence number and timestamp; the
  Mac drops anything out of order or older than its skew window. A recorded
  and replayed network capture can't be used to scroll your Mac later.
- **Dead-link safety:** continuous scrolling has a 250ms timeout — if the
  Watch app is killed or Wi-Fi drops mid-scroll, the Mac stops scrolling
  within a quarter second rather than coasting forever.
- **HealthKit workout session:** the Watch app starts (but never saves) a
  workout session while scroll mode is active, purely to stay alive and
  keep motion updates flowing with your wrist down. See the App Review note
  in `KeepAliveSession.swift` before shipping publicly — Apple reviews
  HealthKit usage closely, and a "fake" workout for keep-alive purposes may
  need a clearer in-app explanation to pass review smoothly.

## Accessibility permission (Mac)

macOS will not let any app post synthetic input events without explicit
user approval. First launch, the Mac app's menu shows a prompt to open
System Settings → Privacy & Security → Accessibility and enable DoomScroll.
This is a one-time, per-Mac step that cannot be automated or skipped —
Apple does not provide a way to pre-approve this from a provisioning
profile or MDM payload for a Developer-ID-distributed app.
