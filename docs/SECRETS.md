# GitHub Secrets Setup

## The default pipeline needs NO secrets

This is deliberate. The main workflow (`build-and-deploy.yml`) produces an
**unsigned** `.ipa` on GitHub's hosted macOS runners. Signing happens later,
on your phone, when AltStore or SideStore installs the app — they sign with
your free Apple ID on-device. That is the only signing flow that actually
works without a paid Apple Developer Program membership:

- Free Apple IDs cannot create App Store Connect API keys (`.p8`), so the
  classic CI signing setup (certificate + provisioning profile in secrets)
  is not available to you at all — those artifacts require a paid account.
- Free-account development certificates are minted interactively (with 2FA)
  by Xcode/AltStore/SideStore and expire after 7 days, which makes them
  useless as static CI secrets.

So: fork the repo, enable Actions, push. No configuration required.

## Optional secrets

| Secret | Used by | Purpose |
|---|---|---|
| `XCODE_XIP_URL` | `xtool-linux-experimental` job | Private URL to a Xcode `.xip` you downloaded from Apple with your own Apple ID. Lets the experimental Linux job extract the Darwin SDK via `xtool setup`. Do **not** point this at a public URL — redistributing the SDK violates Apple's license. |

## Secrets you should NOT create

Earlier drafts of this pipeline called for `APPLE_ID`, `APPLE_PASSWORD`,
`IOS_CERTIFICATE_P8_BASE64`, and `IOS_PROVISION_PROFILE_BASE64`. Don't:

- Putting Apple ID credentials in CI is a real account-security risk, and
  Apple's interactive 2FA breaks headless logins anyway.
- The `.p8`/provisioning-profile flow requires a paid developer account, which
  this project explicitly assumes you don't have.

If you ever join the paid Developer Program, revisit this: proper CI signing
with `fastlane match` or App Store Connect API keys becomes available, and the
7-day expiry problem disappears (1-year profiles).

## How to add a secret

Repository → **Settings** → **Secrets and variables** → **Actions** →
**New repository secret**.
