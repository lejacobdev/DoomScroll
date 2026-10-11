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

Read **[docs/LIMITATIONS.md](docs/LIMITATIONS.md)** first — in particular,
there is no way for an iOS app to scroll other apps directly; that's an iOS
sandboxing boundary, not something this project works around. Mac (and
iPhone via Mirroring) is the real, fully-working path.

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

1. Launch **DoomScrollMac**. It appears in the menu bar. Click it → grant
   Accessibility access when prompted (System Settings → Privacy & Security
   → Accessibility).
2. Click **Pair iPhone…** in the Mac menu — shows a QR code.
3. On your iPhone, open **DoomScroll** → **Scan to pair** → scan that code.
4. Open **DoomScroll** on your Apple Watch.
5. Double-tap your fingers (or tap the on-screen button) to start scroll
   mode, flick or tilt your wrist, double-tap again to stop.

## CI and releases

See **[docs/RELEASE.md](docs/RELEASE.md)**: secrets setup, TestFlight
upload, and the notarized Mac release path. You need a paid Apple Developer
Program account for both.

## Testing

```bash
swift test --package-path Packages/ScrollCore
```

27 tests cover the wire protocol (HMAC auth, replay/staleness rejection,
pairing token round-trip), the motion processor (flick detection, tilt
deadzone/scaling, inversion), momentum physics, settings, WatchConnectivity
dictionary encoding, line framing, and a real loopback-TCP integration test
against `ScrollServer` that proves tampered/replayed/wrong-key messages are
actually rejected over the network, not just in the authenticator's own
unit tests.
