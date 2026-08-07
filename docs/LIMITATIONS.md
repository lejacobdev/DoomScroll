# Known Limitations

This document is the honest version of what this project can and cannot do.
Read it before filing a bug that something "doesn't scroll."

## 1. System-wide scrolling of other apps is impossible — by design of iOS

The original goal was Vision Pro-style air scrolling of *any* app (Safari,
Mail, TikTok, …). On stock iOS this cannot be built with public APIs, and no
amount of cleverness changes that:

- **Sandboxing.** A third-party app has no handle on another process's UI.
  There is no window server access, no view hierarchy of other apps, nothing
  to send a scroll to.
- **No `AXUIElement` on iOS.** The accessibility API that lets a Mac app drive
  other apps (`AXUIElementPerformAction`, etc.) is macOS-only. It has no iOS
  counterpart for third parties.
- **`UIAccessibility` is in-process.** `accessibilityScroll(_:)`,
  `UIAccessibilityCustomAction`, and accessibility notifications only reach
  elements inside *your own* app. They are how your app describes itself to
  VoiceOver — not a remote control for other apps.
- **No HID/IOKit event injection.** Synthesizing scroll-wheel or touch events
  system-wide requires private frameworks (`IOHIDEvent`,
  `BackBoardServices`) and entitlements Apple only grants to itself. Private
  API also fails at signing/installation for sideloaded builds and is a
  non-starter.

**What this app does instead:** it scrolls its own content — a demo feed and
a built-in `WKWebView` browser. The browser is the practical workaround: you
can air-scroll *any website*, just inside DoomScroll rather than inside
Safari.

Routes that genuinely achieve system-wide control, all out of scope here:
jailbreak tweaks, Apple's own AssistiveTouch/Switch Control (not scriptable by
apps), or driving a Mac's `AXUIElement` API while mirroring the iPhone
(macOS Sequoia iPhone Mirroring — requires a Mac, which this project avoids).

## 2. Which surfaces scroll, concretely

| Surface | Works? | How |
|---|---|---|
| DoomScroll demo feed (SwiftUI `ScrollView`/`List`) | ✅ | `UIScrollView.setContentOffset` |
| DoomScroll in-app browser (any website) | ✅ | WKWebView's internal scroll view; JS `window.scrollBy` fallback for nested iframes |
| Custom in-app containers without a scroll view | ⚠️ page-at-a-time | in-process `accessibilityScroll(_:)` fallback |
| Safari, Mail, TikTok, any other app | ❌ | impossible with public API (see §1) |
| Home screen / system UI | ❌ | same |

## 3. The Double Tap gesture is only partially available to apps

The system Double Tap gesture (index finger + thumb) is reserved by watchOS.
The only public hook is `.handGestureShortcut(.primaryAction)` (watchOS 11+),
which lets Double Tap press one designated button while your app is frontmost.
That is exactly how the Air Scroll toggle is wired.

On watchOS 10 there is no API at all, so this app ships an accelerometer-based
double-tap detector (`DoubleTapDetector`). It is a heuristic: expect occasional
missed or phantom detections, and tune `tapThreshold` if needed. The on-screen
button always works.

## 4. Streaming stops when the wrist drops

watchOS suspends third-party apps aggressively. When the screen sleeps or the
app leaves the foreground, motion updates and WatchConnectivity streaming stop
(this is also deliberate: it prevents phantom scrolling and battery drain).
Keep the Watch app frontmost while scrolling. `WKExtendedRuntimeSession` types
don't cover this use case for meaningful extra time.

## 5. WatchConnectivity is best-effort

`sendMessage` at 20 Hz generally holds up over Bluetooth, but frames drop and
stalls happen. Mitigations built in: every command carries a timestamp and the
iPhone drops anything older than 0.5 s; the iPhone ends the session after 1 s
of silence in case the final "stop" message is lost; delta timing is derived
from real inter-arrival times so dropped frames scroll farther, not slower.

## 6. Sideloading the Watch companion is the weakest link

This is the biggest *practical* risk of the whole project:

- **AltStore / SideStore remap bundle IDs** when signing with a free Apple ID.
  The Watch↔iPhone pairing depends on `WKCompanionAppBundleIdentifier`
  matching the iOS app's bundle ID exactly, and remapping breaks that link, so
  the Watch app typically won't install from the Watch app gallery.
- Free-account provisioning for watchOS through sideloaders is unreliable in
  general; results vary by tool and version (Sideloadly, SideStore nightlies).
- **The only fully supported free path** for getting the Watch app onto a
  physical watch is a one-time deploy from Xcode with a free Apple ID — from
  any borrowed or cloud Mac (e.g. a MacinCloud/MacStadium trial hour). After
  that, the 7-day re-sign only affects launching, and rebuilds are still CI's
  job.
- **AltStore PAL** (the EU alternative marketplace) distributes notarized
  marketplace apps; it is not a free-Apple-ID signer for your own IPA. For
  self-signing, use AltStore Classic or SideStore.

The iOS app alone sideloads fine everywhere and is fully usable with the Watch
app installed by any means.

## 7. Free Apple ID constraints

- Apps expire after **7 days** and must be re-signed (AltStore/SideStore
  automate this on-device).
- Maximum **3 sideloaded apps** installed at once.
- **10 App IDs per week** — bundle-ID churn from experiments can hit this cap.
- No push notifications, iCloud, or App Groups. Nothing in this project needs
  them: WatchConnectivity requires no special entitlements.

## 8. Linux builds (xtool) cover only half the project

[xtool](https://github.com/xtool-org/xtool) genuinely cross-compiles iOS apps
on Linux — but it does **not support watchOS targets**, and it needs the
Darwin SDK extracted from a Xcode `.xip` that Apple's license forbids
redistributing (so no public Docker image can include it). That's why the
primary "no Mac required" pipeline runs on GitHub's **free hosted macOS
runners** instead: you still never own, rent, or touch a Mac — GitHub does.
The Docker/xtool path is kept as an experimental, iOS-only job.
