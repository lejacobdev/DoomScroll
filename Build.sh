#!/bin/bash
# Build orchestration for DoomScroll.
#
#   macOS  -> XcodeGen + xcodebuild, full iOS + embedded watchOS build,
#             packaged as an unsigned .ipa (AltStore/SideStore sign at install).
#   Linux  -> experimental xtool path, iOS target ONLY (xtool cannot build
#             watchOS), requires XCODE_XIP_URL for the Apple SDK.
set -euo pipefail

echo "[*] DoomScroll build pipeline"

build_macos() {
    echo "[*] macOS toolchain: XcodeGen + xcodebuild"

    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "[*] Installing XcodeGen..."
        brew install xcodegen
    fi

    echo "[*] Generating Xcode project..."
    xcodegen generate

    echo "[*] Building iOS app (watchOS companion embedded automatically)..."
    xcodebuild build \
        -project DoomScroll.xcodeproj \
        -scheme DoomScroll \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath build \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY=""

    APP_PATH="build/Build/Products/Release-iphoneos/DoomScroll.app"
    if [ -d "$APP_PATH/Watch" ]; then
        echo "[*] Watch app embedded OK"
    else
        echo "[!] WARNING: no embedded Watch app found in $APP_PATH"
    fi

    echo "[*] Packaging unsigned .ipa..."
    rm -rf Payload DoomScroll-unsigned.ipa
    mkdir -p Payload
    cp -R "$APP_PATH" Payload/
    zip -qry DoomScroll-unsigned.ipa Payload
    rm -rf Payload

    echo "[+] Build complete:"
    ls -lh DoomScroll-unsigned.ipa
    echo "[i] Sideload with AltStore/SideStore — they sign with your free Apple ID at install time."
}

build_linux_xtool() {
    echo "[*] Linux toolchain: xtool (EXPERIMENTAL, iOS target only)"
    echo "[!] xtool cannot build watchOS — the Watch companion will NOT be in this build."

    if ! command -v xtool >/dev/null 2>&1; then
        echo "[!] xtool not installed. Build the Docker image first: docker build -t doomscroll-xtool ."
        exit 1
    fi

    if [ ! -d "$HOME/.xtool/sdk" ] && [ -z "${XCODE_XIP_URL:-}" ]; then
        echo "[!] No Darwin SDK installed and XCODE_XIP_URL not set."
        echo "    xtool needs the Apple SDK from a Xcode .xip you downloaded with"
        echo "    your own Apple ID (it cannot be redistributed). Set XCODE_XIP_URL"
        echo "    or run 'xtool setup' interactively."
        exit 1
    fi

    if [ ! -d "$HOME/.xtool/sdk" ]; then
        echo "[*] Fetching Xcode .xip for SDK extraction..."
        curl -fL "$XCODE_XIP_URL" -o /tmp/Xcode.xip
        xtool setup --xip /tmp/Xcode.xip
        rm -f /tmp/Xcode.xip
    fi

    echo "[*] Building iOS target with xtool..."
    xtool build --configuration release

    echo "[+] xtool build finished. Note: output has no Watch app; use the"
    echo "    macOS-runner workflow for the full bundle."
}

case "$(uname -s)" in
    Darwin) build_macos ;;
    Linux)  build_linux_xtool ;;
    *)      echo "[!] Unsupported platform: $(uname -s)"; exit 1 ;;
esac
