<p align="center">
  <img src="docs/screenshots/hero.png" alt="Teamwork Timer: the main window and the menu bar popover" width="100%">
</p>

<h1 align="center">Teamwork Timer</h1>

<p align="center">
  A fast, native macOS menu bar timer for <a href="https://www.teamwork.com">Teamwork.com</a>.<br>
  A SwiftUI rewrite of the old Electron Teamwork Timer, built for Apple silicon.
</p>

<p align="center">
  <a href="https://github.com/doxigo/teamwork-timer/actions/workflows/build.yml"><img src="https://github.com/doxigo/teamwork-timer/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-1D1C39" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-6438E0" alt="Swift 6">
</p>

---

## Why

The original Teamwork Timer is an Electron 4 app that runs under Rosetta and feels it. This one is a small native app that lives in the menu bar, uses Teamwork's own server timers (so a timer you start on the web shows up here, and the other way round), and keeps tracking down to a click or a keystroke.

## Features

- **Menu bar first.** The running timer ticks in the menu bar as time, task and time, a compact badge, or just an icon.
- **A popover for the whole day.** Today's timers and logged time, a week strip with daily totals, one-click Start and Pause, and your daily target from Teamwork.
- **Pinned tasks.** Pin the work you repeat and start it with ⌘1–⌘9.
- **Starred projects, Due Today and Recent** at the top of every picker. Search any task or project, or paste a Teamwork task link.
- **Log with care.** Edit the duration (`1:30`, `1.5h`, `90m`), round up or down to a step you choose, mark the task complete, or log every timer at once.
- **Edit as you go.** Move a running timer to another task, change notes and billable, and edit or delete logged entries.
- **Idle detection.** Come back from a break and choose to keep the idle time, or remove it and continue or stop.
- **Reminders.** A nudge at the end of the working day if timers are left, and an alert for timers left running too long.
- **A library window.** Timers, Today, This Week, Pinned, Starred Projects and My Tasks, with Settings and your account in the same window.
- **Light and Dark Mode**, in Teamwork's palette.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/popover-light.png" alt="Popover in Light Mode"></td>
    <td width="50%"><img src="docs/screenshots/popover-dark.png" alt="Popover in Dark Mode"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/today.png" alt="Today in the main window"></td>
    <td><img src="docs/screenshots/week-dark.png" alt="This Week in Dark Mode"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings.png" alt="Settings"></td>
    <td align="center"><img src="docs/screenshots/menubar-badge.png" alt="Time badge in the menu bar" width="200"><br><sub>The <b>Time badge</b> menu bar style</sub></td>
  </tr>
</table>

<sub>Screenshots use sample data.</sub>

## Install

1. Download `TeamworkTimer.zip` from the latest [release](https://github.com/doxigo/teamwork-timer/releases) (or the newest successful [build](https://github.com/doxigo/teamwork-timer/actions/workflows/build.yml) run's artifacts) and unzip it.
2. Move **Teamwork Timer** to Applications.
3. The app isn't notarized, so macOS blocks the first launch. Either right-click the app and choose **Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Teamwork Timer.app"
   ```

Requires macOS 26 or later.

## Sign in

Open the window (⌘0 from the popover), then **Sign In** at the bottom of the sidebar. Two options:

- **API token** (quickest): in Teamwork, open your profile, choose **Edit My Details**, then **API & Mobile**, and copy the token. Enter your site (for example `acme.teamwork.com`) and the token.
- **Teamwork Sign-In** (OAuth): create an app in your site's Developer Portal (`https://<your-site>/developer`), add `http://localhost:8123` as a redirect URL, and paste its client ID and secret. Your browser opens to sign in and hands the result back to the app.

Credentials are stored in your Keychain. Builds signed without an Apple Developer certificate ask for your login password once after each update; choose **Always Allow**.

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘N | New timer |
| ⌘↩ | Pause the running timer, or resume the last one |
| ⌘1–⌘9 | Start a pinned task (popover) |
| ⌘1–⌘6 | Switch pages (window) |
| ← → | Previous or next day (popover) |
| ⌘0 | Open the main window |
| ⌘, | Settings |
| ⌘R | Refresh |
| ⇧⌘M | Floating mini timer |

A global Start/Pause shortcut can be set in Settings.

## Build from source

You need macOS 26 and either Xcode 26 or the Command Line Tools.

```bash
./check.sh    # assert-based checks for the models, API decoding, parsing and rounding
./bundle.sh   # builds and signs "build/Teamwork Timer.app"
```

`bundle.sh` signs with a self-signed identity it creates once in `.signing/` (git-ignored), so the Keychain keeps recognising the app between local builds. Every push to `main` builds the app on GitHub Actions; pushing a `v*` tag publishes a release with the zipped app.

[DESIGN.md](DESIGN.md) holds the reverse-engineering notes on the old app, the information architecture, and the Teamwork API details.

## Project layout

```
Sources/TeamworkTimer/
  TeamworkTimerApp.swift   scenes and menu commands
  Store.swift              app state, polling, caching, logging rules
  TeamworkClient.swift     Teamwork v3 API (timers, time logs, tasks, projects)
  Auth.swift               Keychain, Launchpad OAuth, loopback redirect server
  Popover.swift            the menu bar popover
  MainWindow.swift         the library window
  Chrome.swift, Brand.swift  the shared design system and palette
Checks/                    assert checks and anonymised API fixtures
```

## Disclaimer

An independent project, not affiliated with or endorsed by Teamwork.com. "Teamwork" and the Teamwork brand colours belong to their owners.
