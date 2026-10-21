#!/bin/sh
# Assert-based checks for the non-UI code; works with Command Line Tools only (no Xcode, no test macros).
set -eu
cd "$(dirname "$0")"
src=Sources/TeamworkTimer
# Command Line Tools only: pin the macOS 26 SDK, because the CLT's macOS 27 SwiftUI needs Xcode's macro
# plugins. With Xcode selected (CI), its own SDK is used.
clt_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
case "$(xcode-select -p)" in */CommandLineTools) [ -d "$clt_sdk" ] && export SDKROOT="$clt_sdk" ;; esac
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -swift-version 6 \
    "$src/Models.swift" "$src/TeamworkClient.swift" "$src/Auth.swift" "$src/Store.swift" "$src/Idle.swift" \
    "$src/Reminders.swift" "$src/Brand.swift" "$src/Chrome.swift" "$src/MenuBarView.swift" \
    Checks/main.swift -o "$out/checks"
"$out/checks" Checks/fixtures
xcrun swiftc -swift-version 6 \
    "$src/Models.swift" "$src/TeamworkClient.swift" "$src/Store.swift" \
    Checks/Store/Services.swift Checks/Store/Transport.swift Checks/Store/main.swift -o "$out/store-checks"
"$out/store-checks"
xcrun swiftc -swift-version 6 \
    "$src/Models.swift" "$src/TeamworkClient.swift" "$src/Store.swift" "$src/Brand.swift" "$src/Chrome.swift" \
    "$src/MenuBarView.swift" "$src/Forms.swift" Checks/Store/Services.swift Checks/Store/Transport.swift \
    Checks/Forms/main.swift -o "$out/form-checks"
"$out/form-checks"
python3 Checks/bundle.py
