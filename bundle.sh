#!/bin/sh
# Builds "build/Teamwork Timer.app" without Xcode.
set -eu
cd "$(dirname "$0")"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    case "$SIGNING_IDENTITY" in
        "Developer ID Application:"*) ;;
        *) echo "Public builds require a Developer ID Application identity." >&2; exit 1 ;;
    esac
    : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
fi
if [ -n "${CI:-}" ] && [ -z "${SIGNING_IDENTITY:-}" ] && [ -z "${UNSIGNED_RELEASE:-}" ]; then
    echo "CI app bundles require SIGNING_IDENTITY and NOTARY_PROFILE (or an explicit UNSIGNED_RELEASE=1). No release was produced." >&2
    exit 1
fi
# Command Line Tools only: pin the macOS 26 SDK, because the CLT's macOS 27 SwiftUI needs Xcode's macro
# plugins. With Xcode selected (CI), its own SDK is used.
clt_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
case "$(xcode-select -p)" in */CommandLineTools) [ -d "$clt_sdk" ] && export SDKROOT="$clt_sdk" ;; esac
swift build -c release
app="build/Teamwork Timer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/TeamworkTimer "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
# ponytail: placeholder .icns; replace with an Icon Composer icon once Xcode is installed
cp Resources/AppIcon.icns "$app/Contents/Resources/"

# Release disk image: the app plus an Applications shortcut to drag it onto.
make_dmg() {
    stage=$(mktemp -d)
    chmod 755 "$stage" # mktemp makes it owner-only; the volume root inherits this
    ditto "$app" "$stage/Teamwork Timer.app"
    ln -s /Applications "$stage/Applications"
    rm -f "$1"
    hdiutil create -volname "Teamwork Timer" -srcfolder "$stage" -format UDZO -ov "$1" >/dev/null
    rm -rf "$stage"
}

# Sign with a stable local identity, not ad hoc: an ad-hoc signature changes every build, and macOS then
# treats each build as a new app (Keychain sign-in unreadable, notification permission lost).
# The self-signed identity lives in its own keychain under .signing/ and never touches the login keychain.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
    codesign --verify --deep --strict "$app"
    # Apple's flow for disk images: sign the image, notarize it (which covers the app inside), staple it.
    archive="build/TeamworkTimer.dmg"
    make_dmg "$archive"
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$archive"
    if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
        xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --wait
    else
        xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    fi
    xcrun stapler staple "$archive"
    xcrun stapler validate "$archive"
    echo "$archive"
    exit 0
fi
# Explicit opt-in only (UNSIGNED_RELEASE=1): an ad-hoc signed, un-notarized archive for a pre-release, used
# until Developer ID secrets exist. Gatekeeper blocks its first launch; the release notes say how to open it.
if [ -n "${UNSIGNED_RELEASE:-}" ]; then
    codesign --force --sign - "$app"
    codesign --verify --deep --strict "$app"
    archive="build/TeamworkTimer.dmg"
    make_dmg "$archive"
    echo "$archive"
    exit 0
fi
keychain="$PWD/.signing/dev.keychain-db"
identity="Teamwork Timer Local Signing"
if [ ! -f "$keychain" ]; then
    mkdir -p .signing
    tmp=$(mktemp -d)
    printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$identity" > "$tmp/cert.cnf"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$identity" -passout pass:dev -out "$tmp/id.p12" 2>/dev/null \
        || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$identity" -passout pass:dev -out "$tmp/id.p12"
    security create-keychain -p dev "$keychain"
    security import "$tmp/id.p12" -k "$keychain" -P dev -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k dev "$keychain" >/dev/null
    rm -rf "$tmp"
fi
security unlock-keychain -p dev "$keychain"
codesign --force --keychain "$keychain" --sign "$identity" "$app"
echo "$app"
