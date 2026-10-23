> [!WARNING]
> **Unsigned build.** This build isn't signed with a Developer ID or notarized by Apple, so macOS blocks its first launch.

**Install**

1. Open `Stint.dmg` and drag **Stint** onto the Applications folder.
2. Open Stint. When macOS says it can't verify the app, click **Done**.
3. Open **System Settings › Privacy & Security**, scroll down to **Security**, find the message about Stint and click **Open Anyway**. The button is there for about an hour after you tried to open the app.
4. Enter your login password, then confirm that you want to open Stint.

Or remove the download quarantine in Terminal instead:

```bash
xattr -dr com.apple.quarantine "/Applications/Stint.app"
```

Stint 0.5.5 and later install their own updates (Settings › Updates).

Requires macOS 26 on Apple silicon. Because the build isn't Developer ID signed, macOS asks for your login password once after each update so the app can read its saved sign-in; choose **Always Allow**.

