> [!WARNING]
> **Unsigned pre-release.** This build isn't signed with a Developer ID or notarized by Apple, so macOS blocks its first launch.

**Install**

1. Unzip `TeamworkTimer.zip` and move **Teamwork Timer** to Applications.
2. Right-click the app and choose **Open**, then confirm. Or run:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Teamwork Timer.app"
   ```

Requires macOS 26 on Apple silicon. Because the build isn't Developer ID signed, macOS asks for your login password once after each update so the app can read its saved sign-in; choose **Always Allow**.

