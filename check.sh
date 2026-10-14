#!/bin/sh
# Assert-based checks for the non-UI code; works with Command Line Tools only (no Xcode, no test macros).
set -eu
cd "$(dirname "$0")"
src=Sources/TeamworkTimer
out=$(mktemp -d)
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -swift-version 6 \
    "$src/Models.swift" "$src/TeamworkClient.swift" "$src/Auth.swift" "$src/Store.swift" "$src/Idle.swift" \
    "$src/Reminders.swift" Checks/main.swift -o "$out/checks"
"$out/checks" Checks/fixtures
