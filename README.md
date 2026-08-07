# DoomScroll ⌚📱

Vision Pro-style **air scrolling for iPhone, driven by your Apple Watch**:
double tap to enter scroll mode, tilt your wrist to scroll — no touching the
phone. Built to be compiled, packaged, and sideloaded **without owning a Mac
or a paid Apple Developer license**.

```
 ┌─────────────┐   double tap        ┌──────────────────────┐
 │ Apple Watch │ ─────────────────►  │  scroll mode ON      │
 │  watchOS 10+│   gyro @ 20 Hz      │  haptic + UI state   │
 └──────┬──────┘                     └──────────────────────┘
        │  WatchConnectivity sendMessage
        │  { command, velocityX, velocityY, isActive, timestamp }
        ▼
 ┌─────────────┐   velocity → delta  ┌──────────────────────┐
 │   iPhone    │ ─────────────────►  │ frontmost scroll view│
 │   iOS 17+   │   20 Hz, smoothed   │ feed / in-app browser│
 └─────────────┘                     └──────────────────────┘
```

## ⚠️ Read this first: what it can and cannot do

**This app scrolls its own content, not other apps.** iOS sandboxing makes
"system-wide" scrolling of Safari/Mail/etc. impossible with public APIs — the
macOS-style accessibility remote-control API does not exist on iOS, and event
injection is private API. The practical workaround is built in: an **in-app
browser tab**, so you can air-scroll any website, plus a demo feed. The full
technical explanation is in [docs/LIMITATIONS.md](docs/LIMITATIONS.md) —
read it, it's the most important file in this repo.

Also important:

- The system **Double Tap** gesture reaches third-party apps only via
  `.handGestureShortcut(.primaryAction)` on **watchOS 11+**. On watchOS 10 an
  accelerometer-based detector approximates it (and the on-screen button
  always works).
- Getting the **Watch companion installed via sideloading is unreliable**
  (bundle-ID remapping breaks Watch↔iPhone pairing). The iOS app works
  standalone; see [LIMITATIONS §6](docs/LIMITATIONS.md) for the honest
  options.

## No Mac required — how the pipeline works

GitHub-hosted **macOS runners are free for public repositories**, and they are
the only toolchain that can compile watchOS. You never touch a Mac; GitHub
does. (The Linux/xtool + Docker path exists as an experimental job, but xtool
can't build watchOS and needs a user-supplied Apple SDK — details in
[LIMITATIONS §8](docs/LIMITATIONS.md).)

The output is an **unsigned .ipa** — that's correct, not a bug: AltStore and
SideStore sign apps **with your free Apple ID, on-device, at install time**.
No certificates, no secrets, no paid account.

### Setup (once)

1. **Fork** this repository (keep it public so macOS runners are free).
2. Enable **Actions** in your fork (Actions tab → enable workflows).
3. That's it. No secrets needed — see [docs/SECRETS.md](docs/SECRETS.md).

### Build & install (each time)

1. Push to `main` (or run the workflow manually from the Actions tab).
2. Download **`DoomScroll-sideload`** from the run's Artifacts
   (or from the Release, if you pushed a tag like `v1.0.0`).
3. Sideload `DoomScroll-unsigned.ipa` with **AltStore Classic** or
   **SideStore** using your free Apple ID.
   - Note: **AltStore PAL** (EU marketplace) can't sign personal IPAs; use
     AltStore Classic/SideStore for this.
4. Free-Apple-ID apps expire after **7 days**; AltStore/SideStore re-sign
   automatically when they can.
5. Watch app: check the Watch app on iPhone → Available Apps. If it won't
   install (common with sideloading — see limitations), the iOS app still
   works; the guaranteed path is a one-time Xcode deploy from any borrowed
   or cloud Mac.

## Using it

1. Open DoomScroll on the iPhone, pick the **Feed** or **Browser** tab.
2. Open DoomScroll on the Watch. **Double tap** (watchOS 11+) or press
   **Air Scroll**. The Watch taps back and shows scroll mode.
3. **Tilt your wrist** toward/away from you to scroll vertically; **roll**
   it for horizontal. A banner on the phone shows live state + a
   sensitivity slider.
4. Double tap again (or press Stop) to exit. Lowering your wrist also ends
   the session automatically.

Tune sensitivity, axis inversion, and haptics in the phone's **Settings** tab.

## Repository layout

```
Sources/
  Shared/ScrollCommand.swift        Wire format Watch ↔ iPhone
  Watch/                            watchOS app (SwiftUI)
    Managers/MotionService.swift      50 Hz device motion, drift suppression
    Managers/DoubleTapDetector.swift  accelerometer double-tap (watchOS 10 fallback)
    Managers/WatchSessionManager.swift  WCSession streaming, 50 ms throttle
    Managers/ScrollModeController.swift state machine + haptics
  iOS/                              iOS app (SwiftUI)
    Accessibility/AccessibilityScroller.swift  finds & drives scroll views
    Managers/ScrollDispatcher.swift   velocity → deltas, background queueing
    Managers/PhoneSessionManager.swift  WCSession listener, stale-drop
    Views/                            Feed, Browser, Settings, StatusBanner
project.yml                         XcodeGen spec (project generated in CI)
.github/workflows/build-and-deploy.yml  main pipeline → unsigned .ipa artifact
.github/workflows/test.yml          PR validation (simulator build)
Dockerfile + Build.sh               experimental Linux/xtool path (iOS only)
docs/LIMITATIONS.md                 ← read this
docs/SECRETS.md                     why no secrets are needed
```

## Local development (optional, if you do have a Mac)

```sh
brew install xcodegen
xcodegen generate
open DoomScroll.xcodeproj   # run on device with your free Apple ID
# or: ./Build.sh            # unsigned .ipa, same as CI
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Watch says "iPhone unreachable" | iPhone app not running/foregrounded; WatchConnectivity `sendMessage` needs a live counterpart |
| Scrolling feels laggy or jumpy | Bluetooth congestion — commands are smoothed and stale-dropped, but 20 Hz over BT is best-effort |
| Content scrolls the wrong way | Flip "Invert vertical" in Settings |
| Slow phantom scrolling | Shouldn't happen (gyro drift is zeroed after 200 ms below 0.1 rad/s) — file an issue with your Watch model |
| Nothing scrolls in some app screen | Only DoomScroll's own content can scroll — see [docs/LIMITATIONS.md](docs/LIMITATIONS.md) |
| Watch app won't install | Sideloading limitation — [LIMITATIONS §6](docs/LIMITATIONS.md) |
