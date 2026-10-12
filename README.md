# DoomScroll

Scroll your Mac — and your iPhone, through iPhone Mirroring — hands-free
with your Apple Watch. Double-tap your fingers to start, flick or tilt your
wrist to scroll, double-tap again to stop.

```
Apple Watch  →  (direct Wi-Fi, or relayed via iPhone)  →  Mac menu-bar app
                                                              │
                                                    CGEvent scroll-wheel
                                                              │
                                          ┌───────────────────┴───────────────────┐
                                          ▼                                       ▼
                                 any Mac app, under                     iPhone Mirroring window
                                   the pointer                            (scrolls your iPhone)
```

**Digital Crown:** turning the Crown on your Watch scrolls too, with or
without wrist scroll mode. If it goes the wrong way, use *Reverse Digital
Crown* in the iPhone app.

**No Mac?** Choose **This iPhone** in the app (or tap *I don't have a Mac*
during setup). The Watch then scrolls the DoomScroll browser on your iPhone,
so any website works, with nothing else needed.

Read **[docs/LIMITATIONS.md](docs/LIMITATIONS.md)** first — in particular,
there is no way for an iOS app to scroll other apps directly (Safari,
Instagram, ...); that's an iOS sandboxing boundary, not something this
project works around. Without a Mac, scrolling is limited to the DoomScroll
browser. Mac (and iPhone via Mirroring) is the path that reaches other apps.

## Repository layout

```
Packages/ScrollCore/     Shared Swift package: wire protocol + HMAC auth,
                          the motion→scroll algorithm, momentum physics,
                          Bonjour client/server, Keychain, settings.
                          Platform-agnostic logic lives here and is unit
                          tested with `swift test` — no simulator needed.
Sources/Watch/            watchOS app: motion capture, double-tap, UI.
Sources/iOS/               iOS app: pairing (QR scan), settings, WatchConnectivity relay.
Sources/Mac/               Mac menu-bar app: Bonjour server, CGEvent injection,
                          pairing QR code, Accessibility permission flow.
project.yml               XcodeGen spec — generates DoomScroll.xcodeproj
                          (never committed; see Quick start).
.github/workflows/        CI: PR validation, TestFlight release, Mac release.
docs/                     RELEASE.md (CI/secrets setup), LIMITATIONS.md.
```

## Quick start (local Xcode)

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # fill in your Team ID
xcodegen generate
open DoomScroll.xcodeproj
```

Two schemes: **DoomScroll** (iOS + embedded Watch app) and **DoomScrollMac**
(the menu-bar app). Run `DoomScrollMac` directly on your Mac; run
`DoomScroll` on your iPhone (TestFlight or a device build — AirDrop-style
local Watch pairing needs a real device, not the Simulator, for
WatchConnectivity).

## First run

The iPhone app walks you through everything:

1. **Mac:** launch DoomScrollMac (menu bar) and allow Accessibility. The
   menu shows a checklist until setup is done.
2. **Pair:** in the Mac menu choose *Pair iPhone*, then scan the code from
   the iPhone app's setup flow.
3. **Watch:** open DoomScroll on your Apple Watch.
4. **Calibrate:** two quick flicks on the Watch teach it which way you
   scroll, so wrist side and crown position never matter.
5. Double-tap your fingers to start, flick your wrist, double-tap to stop.

## CI and releases

See **[docs/RELEASE.md](docs/RELEASE.md)**: secrets setup, TestFlight
upload, and the notarized Mac release path. You need a paid Apple Developer
Program account for both.

## Testing

```bash
swift test --package-path Packages/ScrollCore
```

34 tests cover the wire protocol (HMAC auth, replay/staleness rejection,
pairing token round-trip), the motion processor (flick detection, tilt
deadzone/scaling, inversion), momentum physics, wrist calibration, settings, WatchConnectivity
dictionary encoding, line framing, and a real loopback-TCP integration test
against `ScrollServer` that proves tampered/replayed/wrong-key messages are
actually rejected over the network, not just in the authenticator's own
unit tests.
