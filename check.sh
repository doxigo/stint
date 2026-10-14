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
xcrun swiftc -swift-version 6 \
    "$src/Models.swift" "$src/TeamworkClient.swift" "$src/Auth.swift" "$src/Store.swift" "$src/Idle.swift" \
    "$src/Reminders.swift" Checks/main.swift -o "$out/checks"
"$out/checks" Checks/fixtures
