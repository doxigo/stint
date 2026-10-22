# Stint for Teamwork — native rewrite

Stint is a native SwiftUI time tracker for Teamwork.com, replacing Teamwork's Electron *Teamwork Timer 2.6.2*. It was called Teamwork Timer until 0.1.0; the bundle ID (`com.doxigo.TeamworkTimer`), Keychain service and executable keep that name so sign-in and settings carry over.
This file holds the reverse-engineering findings and the five design deliverables required before building
(archetype, information architecture, command map, state + data model, accessibility plan).

---

## 0. Decisions

| # | Decision | Chosen |
|---|---|---|
| D1 | **Sign-in.** The old app's OAuth client ID/secret are hard-coded in its bundle; we must not reuse them. | **Both in M1.** A personal API token (Basic auth), and Launchpad OAuth using *your own* registered client (ID/secret entered in Settings, stored in Keychain; loopback redirect). **For Teamwork's integrations directory:** Stint's own client, injected at build time from CI secrets. Teamwork's App Login Flow in a browser sheet (`ASWebAuthenticationSession`) redirecting to `stint://oauth/callback` (or Teamwork's callback in Stint's own window, chosen at build time). See [Built-in sign-in](#built-in-sign-in). |
| D2 | **Where timers live.** Old app: local-only NeDB, never synced. | **Teamwork v3 server timers** (`/projects/api/v3/me/timers`). |
| D3 | **Minimum macOS.** | macOS 26 (Tahoe): Liquid Glass comes free from system components; Apple-silicon native. |
| D4 | **Toolchain.** Only Command Line Tools are installed (Swift 6.4, macOS 27 SDK); no Xcode. | SwiftPM + a small bundling script. Install Xcode later for Icon Composer, notarization and Instruments. |

---

## 1. What the old app does (reverse engineering)

**Method.** REA 6.4.0, static only (nothing launched, no network).
- DMG inventory: `ev_b5eecf5c…01bd` (4,486 entries, integrity verified).
- `app.asar` JS reconstruction: `ev_b2a3ab70…c7dd`.
- Installed `/Applications/Teamwork Timer.app` is byte-identical to the DMG (`app.asar` sha256 `73edf5eb…6aa3`).

Line numbers below refer to `js/app.js` inside the extracted asar unless noted. O = observed in code, I = inferred.

### 1.1 Platform (O)
- Electron **4.2.12** (2019), binary **x86_64 only**, so it runs under Rosetta on Apple silicon.
- `main.js:32-46` disables the sandbox and every GPU path (`no-sandbox`, `disable-gpu*`, `disableHardwareAcceleration`). This explains most of the sluggishness.
- UI stack: jQuery + Knockout + Bootstrap + moment-timezone (929 KB). The whole `npm` package ships as a runtime dependency.
- Frameless 800×650 window; the close button hides it; single-instance lock.
- Updates via electron-updater from S3 bucket `tw-open/timer`.

### 1.2 Auth (O)
- Launchpad OAuth authorization code flow:
  1. Opens `www.teamwork.com/launchpad/login?redirect_uri=http://127.0.0.1:8123…` (5008).
  2. Catches the redirect in `will-navigate`; nothing actually listens on 8123 (5009-5019).
  3. Exchanges the code at `POST /launchpad/v1/token.json` (592-602).
- The token response carries `installation{apiEndPoint, region, …}` and `user{…}`. Every call goes to `installation.apiEndPoint`, with headers `Authorization: Bearer`, `X-Set-WWW-Authenticate: false`, `TW-Timer: true` (356-395).
- Multiple accounts are keyed `installationId_userId`.
- The token is stored **in plain text** in `~/Library/Application Support/timer.db` (chmod 600). There is no refresh; a 401 reopens login.

### 1.3 API surface (O): v1 only, no server timers, no tags

| Method | Path | Purpose |
|---|---|---|
| GET | `me.json?fullprofile=1` | date/time format, profile time zone |
| GET | `time/projects.json?pageSize=5000&type=featurenabled[&starredOnly=true]` | project pickers (refetched on every modal open) |
| GET | `projects/{id}/tasklists.json`, `tasklists/{id}/tasks.json` | task pickers |
| GET | `tasks.json?responsible-party-ids=me&filter=today\|upcoming\|overdue\|anytime` | "Import my tasks" |
| POST | `tasklists/{id}/tasks.json` | create task |
| POST | `tasks/{id}/time_entries.json` or `projects/{id}/time_entries.json` | log time `{person-id, date, time, hours, minutes, isbillable, description}` |
| PUT | `tasks/{id}/complete.json` | optionally complete the task after logging |

### 1.4 Timer model (O)
- Local record: `{name, time(sec), startedAt, taskId, projectId, tasklistId, company, estimateMins, description, userId}`.
- No billable flag, no tags, no pause segments.
- **One running timer**; at most one timer per task.
- A 1 s interval writes the elapsed time to NeDB **every second** (1802-1810). The append-only file grows while a timer runs.
- Logging: a Log Time or Bulk Log modal with hours/minutes/date/start/description/billable. Afterwards: optionally mark the task complete, then reset or delete the timer.

### 1.5 Features and settings (O)
- **Main window:**
  - Start/pause button, sortable timer table with configurable columns, search, account switcher.
  - Drag a task URL onto the window to create a timer.
  - Compact mode (210×100, optionally on top, optionally hides the Dock icon).
- **Menu bar:** template icon; title shows the *selected* timer's time; menu Toggle / Show / Exit.
- **Idle:** the `afk` package polls `ioreg`. After 15 min (default) it pauses the timer and auto-resumes when you return. There is **no keep/discard prompt**, and idle time before detection stays counted.
- **Notifications:** timer running over 8 h; "nothing running" 30 min after a stop; timers auto-removed.
- **Settings:** show time in menu bar, show total, blink when paused, stay on top, hide Dock icon in compact mode, starred projects only, profile time zone, reset instead of delete, mark task complete, pause when idle (15 min), auto-remove deleted/completed tasks, start at login (hidden on Mac).

### 1.6 Bugs and debt the rewrite fixes (O unless marked)
1. Rosetta + disabled GPU + per-second disk writes → sluggish (I: also battery drain).
2. Hard-coded OAuth secret and Sentry key; plaintext token; request bodies written to logs.
3. Broken code paths:
   - `app.auth.login` and `app.auth.authenticate` don't exist, so every re-login retry crashes.
   - `account.authenticated` is never set, so the task-status refresh never runs.
   - `SelectProject` calls an undefined dialog (5758).
4. Accuracy:
   - Sleep counts as tracked time (I).
   - Minutes can round to "0h 60m".
   - The logged start time is the last resume, not the first start.
5. Timers never leave the Mac: they don't appear in Teamwork's web or mobile apps.

**Unknowns:** runtime behaviour wasn't observed (static analysis only). Server-side effects of `TW-Timer: true` are unknown.

---

## 2. Patterns worth adopting

Common patterns from menu bar time trackers that fit this app.

| Adopt | Why |
|---|---|
| **Favorites as project + task pairs**, one-click Start, auto-hidden when the task closes | This is the "pinned repetitive tasks" feature, done right |
| Pinned projects first in every picker; "pinned only" filter | Starred projects become useful everywhere |
| Menu-bar title with live time, configurable (task · project · H:MM, or today's total); colored icon while running | Most-used surface |
| Menu-bar menu: Stop / Continue latest + 3 recents | Zero-window workflow |
| **Idle prompt with 4 choices** (keep / discard and continue / discard and stop / log idle as a new entry), sleep- and lock-aware | Fixes the old app's silent pause |
| "Forgot to track" reminder with Start / Continue / Snooze actions, working hours only | The old app doesn't do this |
| Forgiving duration input: `1:30`, `1.5`, `1,5`, `:45`, `90m`, `1h30` | Fast manual logging |
| Wrong-day guard ("Start today / Start on Monday") | Prevents misfiled time |
| Opt-in global shortcuts (unset by default, recorder rejects conflicts) | Avoids stealing system shortcuts |
| Stop-race guard ("timer changed elsewhere, not stopped") | Needed once timers live on the server |
| Optimistic UI + Undo toasts | Feels instant |

**Skipped (YAGNI for now):** autotracker rules, activity timeline, ML suggestions, Pomodoro, calendar sync, AI chat. Revisit after M3.

---

## 3. Design deliverables

### 3.1 App archetype
**Menu-bar app with a library + detail window.**
- Daily use happens in the menu bar (start, stop, pinned, recent).
- A `NavigationSplitView` window handles review and editing: timesheet, starred projects, my tasks.

### 3.2 Information architecture

**Menu bar (`MenuBarExtra`, window style)**
```
[▶ 1:23  Website › Fix nav]   ← status item title (configurable)
┌───────────────────────────────┐
│ Running: Website › Fix nav    │  Pause · Stop & Log…
│ "notes…"         1:23:04      │
├───────────────────────────────┤
│ 🔍 Start a timer…  (⌘K)        │  search projects, tasks, pinned
├───────────────────────────────┤
│ PINNED          1–9 to start  │
│ RECENT          last 5 combos │
├───────────────────────────────┤
│ Today 5:40 · Open Window ⌘0 · Settings ⌘, │
└───────────────────────────────┘
```

**Main window: sidebar sections (stable order, for muscle memory)**
1. **Timers**: all server timers (running and paused), with a total.
2. **Today**: time logged today plus timers; day navigation.
3. **This Week**: 7-day strip with daily totals; "Return to today".
4. **Pinned**: project + task (+ description, billable) templates.
5. **Starred Projects**: from Teamwork; expand to task lists and tasks.
6. **My Tasks**: assigned to me, filtered by Today / Overdue / Upcoming / Anytime.

**Detail:** a list (content layer, no glass).
**Inspector** (trailing): edit project, task, description, billable, tags, duration, date.
**Toolbar:** primary *New Timer* (+), search, Refresh. The sidebar groups pages under Time (Timers, Today, This Week) and Work (Pinned, Starred Projects, My Tasks); its footer holds the account (avatar, name, site → Account page) and a Settings gear (⌘,). There is no separate Settings window.

**Window pages use the popover's parts** (`Page` in `MainWindow.swift`): full-width rows, `RowDivider`, pinned `SectionHeader`s, purple hover wash. Starred Projects drills into a project page (Project / Tasks, toolbar search) like the popover's picker. The sidebar draws its own purple selection, because `List(selection:)` paints the system accent and the app can't set an accent color without an Xcode-compiled asset catalog.

**Windows:** one main window, plus the status item's popover. (A floating mini timer was built, then removed on 2026-10-20: the menu bar covers it.)

### 3.3 Command map
Every command is defined once (an `AppCommand` enum) and invoked from menus, toolbar, menu bar and context menus alike.

Built:

| Menu | Command | Shortcut |
|---|---|---|
| App | Settings… | ⌘, |
| File | New Timer… (search, pinned, recent, starred) | ⌘N |
| Edit | Undo / Redo / Cut / Copy / Paste / Select All | standard |
| Timer | Pause Timer / Resume Last Timer | ⌘↩ |
| | Refresh | ⌘R |
| View | Timers / Today / This Week / Pinned / Starred Projects / My Tasks | ⌘1 … ⌘6 |
| | Show Sidebar | ⌃⌘S (system) |
| Toolbar (Today, Week) | Previous / Next, Go to Today | ⌘[ / ⌘], ⌘T |
| Window | Main Window | ⌘0 |
| | Minimize, Zoom, Bring All to Front | standard |
| Popover | Start pinned items 1–9 | ⌘1 … ⌘9 |
| Global (opt-in, off by default) | Start/Pause from any app | ⌃⌥⌘T, ⌃⌥⌘P or ⌃⌥Space |

Not yet in menus, but available on each row (buttons and context menu): Stop & Log, Pin/Unpin, Unstar, Open in Teamwork, Discard. Candidate shortcuts once list selection exists: ⌘L, ⌘D, ⇧⌘D, ⇧⌘O, ⌫. A Help menu with real content is also still to do.

In the popover, pinned items use `⌘1`–`⌘9` because plain digits would land in the search field.

### 3.4 State and data model

**Source of truth:** Teamwork for timers, time entries, projects, tasks and stars. The app is a fast client over it.

| Data | Lives in | Notes |
|---|---|---|
| API token, site URL | Keychain | per account; replaces the plaintext NeDB storage |
| Timers | Teamwork v3 `me/timers` | elapsed = `duration` + (now − last start) when running; **no per-second writes** |
| Timers started elsewhere (web, mobile) | polled every 15 s, plus on popover open and on wake | show in the menu bar with live time |
| Pinned items, recents | `UserDefaults` (Codable `WorkItem`) | `{projectId, projectName, taskId?, taskName?, description, billable}`; local because Teamwork has no "pin" concept |
| Starred projects | Teamwork (`projects/starred`, `PUT projects/{id}/star`) | old app used `time/projects.json?starredOnly=true` |
| Settings | `@AppStorage` | idle minutes, reminders, menu-bar title parts, Dock icon, … |
| Projects/tasks cache | memory (+ disk cache later) | fetched once, refreshed on ⌘R or wake |

**Structure (Swift 6 strict concurrency):**
- `actor TeamworkClient`: the single HTTP layer with async functions; owns auth headers and rate-limit retries.
- `@MainActor @Observable final class Store`: timers, pins, selection, plus the command handlers.
- Views are pure, and live time uses `Text(timerInterval:)` / `TimelineView`. **No app-level ticking timer.**
- **Undo:** an `UndoManager` covers local edits (pins, inspector fields). Destructive server actions (delete timer, discard) use an optimistic 5 s Undo toast before the request is sent.
- **Idle:**
  - `CGEventSource.secondsSinceLastEventType` polled every 15 s, only while a timer runs.
  - `NSWorkspace` sleep/wake and screen-lock notifications.
  - The 4-choice prompt then adjusts the timer.
- **Reminders:** `UserNotifications` with action buttons (Start pinned · Resume last · Snooze 60 m), only inside working hours.
- **Launch at login:** `SMAppService.mainApp`.

### 3.5 Accessibility plan
- **VoiceOver:**
  - Every control has a label.
  - The timer reads e.g. "Website, Fix nav, running, 1 hour 23 minutes".
  - Rows expose Start/Pause/Log as accessibility actions.
- **Keyboard:** every command in §3.3 is reachable without a mouse, with full Tab navigation and focus rings. Single-letter keys turn off while a text field or sheet has focus.
- **Not color alone:** running vs paused uses a symbol (`play.fill` / `pause.fill`) and text, not only tint.
- **Reduce Motion:** no blinking (the old "blink when paused" becomes a static badge); transitions become fades.
- **Reduce Transparency / Increase Contrast:** only system materials are used, so they adapt automatically. The UI is tested with both enabled.
- **Text:** system text styles only; layouts tolerate long project and task names and localization.

---

## 4. Build plan

**Stack:** SwiftUI (AppKit only for `NSPanel` and global hotkeys), SwiftPM, no third-party dependencies.
**Bundling:** `swift build -c release`, then a script wraps the binary in a `.app` with `Info.plist` and an ad-hoc codesign.

| Milestone | Scope | Status |
|---|---|---|
| **M1: replace the old app** | Token and OAuth sign-in, projects/tasks, v3 timers (start/pause/resume/complete/delete), menu bar popover (running timer, pinned, recent, search), Log sheet, starred projects, web-started timers via polling | Built |
| **M2: daily-driver polish** | Main window (Timers / Today / Week / Pinned / Starred / My Tasks), idle prompt, reminders, launch at login, duration parser, editable log duration, menus and shortcuts | Built |
| **M3: power features** | Global Start/Pause shortcut (presets, off by default) | Built |

Deferred:
- **Inspector:** the Log sheet covers editing.
- **Shortcut recorder:** presets cover it for now.
- **Wrong-day guard:** Teamwork timers always start now, so it only matters for manual entries.
- **Multiple accounts:** not needed until someone has two sites.
- **Separate ⌘K palette:** the popover search and the ⌘N sheet already are one.

### What's verified, and how
| Area | Evidence |
|---|---|
| Endpoints, params, bodies | Teamwork's official v3 OpenAPI spec: timers incl. `PUT …/timers/{id}.json`, `seconds` backdating, `timelog.Request`, `taskFilter`, `responsiblePartyIds`, `onlyStarredProjects`, `time.json` filters |
| Response decoding | Self-checks decode real responses from your account, fetched read-only through the Teamwork connector: v3 `me`, timelogs, starred projects, tasks |
| Elapsed time | Computed from `intervals` (finished runs) plus `now − lastStartedAt`, so it no longer depends on what `duration` counts |
| Logic | 48 assert checks: elapsed, decoding, duration parser, working hours, URL/OAuth parsing, formats |
| UI | A preview build renders the real views with sample data, captured with `screencapture` |
| Independent code review | 12 findings, all confirmed and fixed. Highlights below. |
| Not yet exercised live | Requests that change data (start, pause, log, delete): the first real run is yours |

**Review fixes:**
- **Duplicate entries:** logging can no longer post an entry twice when deleting the timer fails afterwards.
- **User ID:** fetched again on later polls if it failed at launch, e.g. with "Open at login" before the network is up.
- **Logging an unchanged timer:** uses Teamwork's own "complete" unless you actually edited the duration.
- **"Resume last":** means the timer you used last, not the one created last.
- **Today and Week:** reload after logging, and never show another day's rows.
- **Running interval:** matched by time rather than exact equality.
- **OAuth sign-in:** can be cancelled.
- **Idle detection:**
  - Removes time only up to your last input.
  - Notices you're back even while you're reading.
  - Refreshes timers before asking on wake.
- **Search:** "C++" is encoded correctly.
- **Duration parser:** rejects negatives, hex and exponents.
- **Discard:** confirmation is inline in the popover.
- **Global shortcut:** says when another app already has the combination.

**Hardened against API behaviour the spec leaves open:**
- **Timer edit:** sends the full timer, in case it replaces rather than merges.
- **Resume:** pauses any other running timer first.

**Still to confirm on the first live run:** whether `time.json`'s `startDate`/`endDate` filter by your local day or by UTC. That decides whether early-morning entries show in Today if you're east of UTC.

**Menu bar:** this is the main timer display, as in Harvest. Settings › General › Menu Bar offers:
- **Show:** Task and time, Time (the default) or Icon only. While a timer runs (Highlight while running, on by default) each becomes Harvest's two-tone pill: a purple pause segment beside the text on slate; otherwise a template symbol and title the menu bar tints.
- **Show seconds:** off by default, so it reads like Harvest's "1:23".


A MenuBarExtra label must use plain text refreshed by `Store.menuBarNow`, a one-second ticker that runs only while a timer runs:
- Time-based views (`Text(timerInterval:)`, `TimelineView`) pin the app at 100 % CPU there, measured on macOS 26.
- The label shows only one image and one text, so task and time are a single string.

**Features added after M3:**

| Feature | Where | API |
|---|---|---|
| Edit a running/paused timer: move to another task, notes, billable, tracked time (0:00–24:00; a running timer carries on from it) | Timer row Edit icon (on hover), or right-click › Edit Task or Notes… | `PUT /me/timers/{id}.json` (`taskId: null` for project-only; `seconds` replaces the timer's runs with one that long) |
| Daily target | Popover footer ring "Today 5:40 of 8:00"; Today/Week bar and "x of y" per weekday | Working hours per weekday (v3 `workload.json` include), else `lengthOfDay` from v3 `me` (Mon–Fri); Settings › General can set your own day |
| Due Today | Popover section between Pinned and Recent | `tasks.json?responsiblePartyIds&taskFilter=today` |
| Task links | Paste into the search field, or drop on the popover/window to start | `GET /tasks/{id}.json` |
| End-of-day reminder | Weekdays from 17:00, once, if timers are left; "Log All…" opens the window | local notification |
| Edit/delete logged entries | Today/This Week: right-click or double-click a row (locked entries excluded) | `PATCH`/`DELETE /time/{id}.json` |
| Log All | Popover link (2+ timers), Timers toolbar, end-of-day reminder | sequential `log()` per timer |

All of these are checked visually in the preview build. Task links and the working-day target are covered by `check.sh`. The live requests still need a real run.

**Edit Entry** follows Harvest's edit form without copying it: the task as a field (project over task; click to change it), notes beside a large duration, then the day, start time, end time and Billable on one line. Open in Teamwork sits in the header.

**Picking a day** (Edit Entry, Log Time): `DayButton` says the day in words ("Today", "Yesterday", "Mon 19 Oct") and opens `MonthCalendar` under it, drawn like the week strip. A click or Today picks and closes; ← → ↑ ↓ move the day while it's open; Log Time stops at today. It replaced the stock date picker, whose "2026-10-21, 09:35" stepper field was hard to read. Inline rather than a popover: a second window over the menu-bar popover takes the focus, and the popover closes when it loses it. The start time is AppKit's date picker without its bezel, so 12- or 24-hour follows the system.

**Rounding:** set under Settings › General › Time Logs.
- **Options:** off (the default), up, down or nearest, in steps of 5, 6, 10, 15, 30 or 60 minutes.
- **Where it applies:** to the Log form's duration, which stays editable and shows the tracked time next to it.
- **Rules:**
  - Works on whole minutes, so 1:15:20 rounds up to 1:15.
  - Never rounds to zero.
  - A rounded value is posted as a time entry; an unrounded, untouched one still uses Teamwork's "complete".

**Idle time:** removing idle time sets the timer's time on Teamwork the same way as an edit (below), so the web app agrees and an untouched timer still logs with Teamwork's "complete"; a running timer keeps the time it counted while the prompt was up. If Teamwork doesn't take it (the request fails, or the server ignores `seconds`), Stint keeps the difference locally and subtracts it when you log, so the entry is posted directly (`POST …/time.json`) and the timer deleted.

**Edited time:** the Edit form sends `seconds` so Teamwork holds the new time and the web app agrees; any local idle adjustment is dropped. If the timer still reads otherwise after the edit (a server that ignores `seconds`), Stint keeps the difference locally, like idle time, and the form notes that the web app shows the original time until it's logged.

### Rate limiting

Teamwork allows about 150 requests a minute and answers 429 beyond that. `TeamworkClient.send` handles it for every request:
- **Wait:** `Retry-After` in seconds (capped at 5 minutes), else Teamwork's documented 60 s. An HTTP-date `Retry-After` also gets 60 s.
- **Everyone waits:** after a 429, no request goes out until the wait ends, so paging through a large list or a burst of requests doesn't keep hitting the limit.
- **Retries:** up to 3 per request, then the 429 surfaces as an error ("still rate-limiting… try again in a minute").
- **Writes:** a 429 is refused before Teamwork processes the request, so a time entry's POST is sent again too. Any other failure still goes through the log receipt: a 5xx or timeout leaves the receipt `uncertain` and is never retried automatically. A log refused by every attempt clears its receipt, like any other 4xx, so you can log again.
- **Status:** while requests wait, the error banner area shows "Teamwork is rate-limiting; retrying…" in secondary text (announced to VoiceOver). It isn't an error and can't be dismissed.

### Built-in sign-in

For Teamwork's integrations directory, Stint signs in with its own Developer Portal app, not one each user registers.
- **Redirect, chosen at build time:** `TEAMWORK_REDIRECT` (a GitHub Actions variable in CI). `bundle.sh` writes it to the built app's Info.plist as `TeamworkRedirect` and refuses any other value. Register the same one in the Developer Portal.
  - **`https://www.teamwork.com/callback`:** Teamwork's suggested redirect for the App Login Flow (their API support, Oct 2026). `WebSignIn` (Auth.swift) shows Launchpad's login page in a Stint window (`WKWebView`). Its `decidePolicyFor` cancels any navigation to the callback before it loads, reads `code` and checks `state`, then closes the window. `Launchpad.exchange` follows with the same redirect.
    - Other hosts load as usual, so single sign-on through the customer's identity provider works. The window's subtitle shows the current host, since there's no address bar. Links that open a new window load in this one.
    - The web view uses a non-persistent data store: no Teamwork cookies or storage outlive the window, and each sign-in starts signed out.
    - Closing the window or Settings' **Cancel** cancels. A page that fails to load ends sign-in with its error. The window gives up after 15 minutes, as long as a code lasts. A 4xx from the token exchange says the code wasn't accepted and expires after 15 minutes.
    - Checked off-screen with a placeholder page, then live against Teamwork's login on 2026-10-20. Google sign-in refuses embedded web views, which is why this is no longer the default.
  - **`stint://oauth/callback` (default since 2026-10-20):** the browser flow. `AppRedirect` (Auth.swift) runs an `ASWebAuthenticationSession` with a `.customScheme("stint")` callback. Launchpad's login opens in a system browser sheet that shares the user's browser session: one click when already signed in, password autofill, and Google and SSO, which refuse embedded web views. The session catches the redirect itself and hands back the URL; `callbackQuery` accepts it only with the sign-in's `state`. No URL event or LaunchServices hop is involved, so no other app can intercept it.
    - Its completion handler runs on an XPC queue, so it is `@Sendable`; a main-actor closure crashed there under Swift 6's runtime isolation check.
    - Teamwork accepted `stint://oauth/callback` as a registered redirect, and sign-in was tested live on 2026-10-20.
    - `stint` stays registered in `CFBundleURLTypes`; `AppDelegate` swallows stray `stint:` URLs (an old browser tab) before SwiftUI would route them to a scene.
  - Teamwork's verification checklist asks for https-only redirects, and localhost redirects were sunset for dynamically registered apps on 1 Aug 2026.
- **Client:** `bundle.sh` writes `TEAMWORK_CLIENT_ID` and, if set, `TEAMWORK_CLIENT_SECRET` into the built app's Info.plist. The release workflow passes them from GitHub secrets of the same names. The repo's Info.plist never has them; `Checks/bundle.py` checks both.
- **Sign-in screen:** with a built-in client, Account shows one **Sign in with Teamwork** button. **Advanced** reveals API Token and Your Own App. Without one (local builds, forks), it falls back to those two, as before.
- **Your own app** also accepts `stint://oauth/callback` as its redirect. The loopback default (`http://localhost:8123`) stays, so existing registrations keep working.

**The secret-exposure question (answered: ship it).** Teamwork's API support confirmed the client secret is simply part of the App Login Flow, with no PKCE or public client, so releases set both GitHub secrets (option 1 below). Launchpad's token exchange (`POST /launchpad/v1/token.json`) requires `client_secret` and has no PKCE. A desktop app can't keep a secret: anything in a public DMG can be read out of the bundle in minutes (`plutil -p Stint.app/Contents/Info.plist`; obfuscation only slows that down).
- **What a leaked secret allows:** someone else can run the code exchange as Stint, for example another client that shows "Stint" on Teamwork's consent screen. They still need the user to sign in and approve. Both redirects are caught inside Stint (the browser session's own callback, or Stint's window), so another app registering `stint:` can't intercept a Stint sign-in's code.
- **The code is ready for each answer:**
  1. *Shipping the secret is acceptable* (common for desktop OAuth without PKCE): set both GitHub secrets. Nothing else changes.
  2. *Teamwork treats Stint as a public client* (exchange without a secret, or PKCE added later): set only `TEAMWORK_CLIENT_ID`. The exchange then leaves `client_secret` out. PKCE would add `code_challenge` to `Launchpad.loginURL` and `code_verifier` to `Launchpad.tokenRequest`.
  3. *The secret must stay server-side:* a small token-exchange endpoint (for example a Cloudflare Worker) holds the secret and turns the code into a token. Stint would post the code there instead of to Launchpad, a change confined to `Launchpad.tokenRequest`. Not built: it adds a service to run.
- **Also Teamwork's to confirm:** whether a `stint://` redirect can be registered as is (their example is `customprotocolapp://…`). A reverse-DNS scheme (`com.doxigo.stint:/oauth`) avoids accidental clashes with another app. Switching changes `appRedirect`, Info.plist and their checks.

### Build and run
```sh
./check.sh                           # assert checks for the non-UI code (Checks/main.swift + fixtures)
./bundle.sh                          # → /Applications/Stint.app (arm64, local signing identity)
open /Applications/Stint.app
```
- Both scripts pin the macOS 26 SDK: the CLT's macOS 27 SwiftUI needs Xcode's macro plugins.
- **Signing:** `bundle.sh` signs with a self-signed "Teamwork Timer Local Signing" identity, created once in `.signing/` (its own keychain, git-ignored, not in the search list).
  - An ad-hoc signature changes with every build, so macOS treated each build as a new app and the Keychain sign-in became unreadable after every rebuild.
  - The designated requirement is now `identifier com.doxigo.TeamworkTimer + certificate leaf`, which is stable across builds.
  - **Remaining limit:** Keychain entries also carry a partition list tied to an Apple team ID, so a self-signed build still asks for the login password once after each update. An "allow all applications" access list doesn't change that; this was tested. Signing with an Apple Development certificate via Xcode removes the prompt.
- `check.sh` stands in for `swift test`. The CLT ship neither XCTest nor the Swift Testing macros, so the checks are plain asserts compiled with `swiftc`.
- `Checks/fixtures/` are real v3 responses, anonymized.
