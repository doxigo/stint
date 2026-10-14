#!/bin/sh
# Builds "build/Teamwork Timer.app" without Xcode.
set -eu
cd "$(dirname "$0")"
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

# Sign with a stable local identity, not ad hoc: an ad-hoc signature changes every build, and macOS then
# treats each build as a new app (Keychain sign-in unreadable, notification permission lost).
# The self-signed identity lives in its own keychain under .signing/ and never touches the login keychain.
if [ -n "${CI:-}" ]; then
    # CI starts fresh every run, so a self-signed identity would be new each time anyway: ad hoc is equivalent.
    codesign --force --sign - "$app"
    echo "$app"
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
