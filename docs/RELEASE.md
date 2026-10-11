# Releasing DoomScroll

Three workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `test.yml` | every PR / push to `main` | `swift test` on ScrollCore + unsigned Simulator builds. No secrets. |
| `release-testflight.yml` | push tag `ios-v*`, or manual | Archives DoomScroll (+ embedded Watch app), uploads straight to App Store Connect / TestFlight. |
| `release-mac.yml` | push tag `mac-v*`, or manual | Archives DoomScrollMac, signs with Developer ID, notarizes, staples, attaches to a GitHub Release. |

The Mac app ships outside the Mac App Store: `project.yml` sets
`com.apple.security.app-sandbox: false` on purpose, because posting scroll
events into other apps (`CGEvent` + the Accessibility API) requires living
outside the sandbox. That's incompatible with Mac App Store distribution, so
Developer ID + notarization is the only path for this app, not a workaround.

## One-time setup

### 1. Apple Developer Program account

You said you now have a paid account — that's required for both TestFlight
and a Developer ID certificate. Note your **Team ID** (developer.apple.com →
Membership details, 10 characters).

### 2. App Store Connect API key (used by both release workflows)

developer.apple.com → Users and Access → **Integrations** → App Store Connect
API → "+". Role: **App Manager** is enough.

- Download the `.p8` once — Apple only lets you download it once.
- Note the **Key ID** and **Issuer ID** shown on that page.

### 3. Developer ID Application certificate (Mac release only)

Xcode → Settings → Accounts → your team → **Manage Certificates** → "+" →
**Developer ID Application**. Export it from Keychain Access as a `.p12`
with a password you choose.

### 4. Register the app in App Store Connect

App Store Connect → Apps → "+" → New App. Platform iOS, bundle ID
`$(DOOMSCROLL_BUNDLE_PREFIX)` from `Config/Local.xcconfig` (e.g.
`com.yourname.doomscroll`). The Watch app doesn't need its own listing — it
rides along embedded in the iOS build.

### 5. GitHub repository secrets and variables

Settings → Secrets and variables → Actions.

**Repository variable** (not secret — it's not sensitive):

| Name | Value |
|---|---|
| `DOOMSCROLL_BUNDLE_PREFIX` | Your chosen bundle ID, e.g. `com.yourname.doomscroll` |

**Secrets:**

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `ASC_API_KEY_ID` | Key ID from step 2 |
| `ASC_API_ISSUER_ID` | Issuer ID from step 2 |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy`, paste the result |
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i YourCert.p12 \| pbcopy`, paste the result (Mac release only) |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `CI_KEYCHAIN_PASSWORD` | Any password — used only for the throwaway CI keychain |

The `.p8` and `.p12` files never touch the repo; the workflows decode the
base64 secret into a temp file at run time and delete it afterward
(`rm -rf ~/private_keys`, `security delete-keychain`).

## Local setup (optional, for building in Xcode)

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# edit Config/Local.xcconfig: your Team ID and bundle prefix
brew install xcodegen
xcodegen generate
open DoomScroll.xcodeproj
```

Pick the **DoomScroll** scheme for iOS+Watch (run on your iPhone or the
Simulator), or **DoomScrollMac** for the Mac app (run directly — menu-bar
apps don't need a device picker).

## Cutting a release

```bash
git tag ios-v1.0.0 && git push origin ios-v1.0.0   # → TestFlight
git tag mac-v1.0.0 && git push origin mac-v1.0.0   # → GitHub Release (notarized .zip)
```

Or run either workflow manually from the Actions tab (`workflow_dispatch`).

TestFlight builds need an export compliance answer and internal/external
tester setup in App Store Connect the first time — `ITSAppUsesNonExemptEncryption: false`
in `project.yml` answers the encryption question automatically.
