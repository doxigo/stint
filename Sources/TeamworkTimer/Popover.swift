import SwiftUI

/// The menu bar popover, modelled on Harvest's: day header, week strip with daily totals,
/// the day's timers and logged entries with one Start button each, and a bottom bar.
struct MenuBarView: View {
    @Environment(Store.self) private var store

    enum Screen: Equatable {
        case day, newTimer, pinned, logAll, summary
        case log(TWTimer), edit(TWTimer), editEntry(TimeEntry), logWork(WorkItem)
    }

    @State private var screen = Screen.day
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// Bumped on each open of the (reused) popover, to reload.
    @State private var opens = 0

    private var calendar: Calendar { .current }
    private var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: day)! }
    private var isToday: Bool { calendar.isDateInToday(day) }
    /// nil until the week has loaded once (then cached in the store).
    private var weekEntries: [TimeEntry]? { store.weeks[week.start] }

    var body: some View {
        Group {
            if !store.isSignedIn {
                signedOut
            } else {
                switch screen {
                case .day: dayScreen
                case .newTimer:
                    VStack(spacing: 0) {
                        ScreenHeader("New Timer") { screen = .day }
                        WorkPicker(maxHeight: 420) { item in start(item) }
                    }
                case .summary:
                    TimeSummary(back: { screen = .day }, openWeek: { show(.week) })
                case .pinned:
                    VStack(spacing: 0) {
                        ScreenHeader("Pinned") { screen = .day }
                        PinnedList(log: { screen = .logWork($0) }) { item in start(item) }
                    }
                case .logAll: LogAllView { screen = .day }
                case .log(let timer): LogView(timer: timer) { screen = .day }
                case .edit(let timer): EditTimerView(timer: timer) { screen = .day }
                case .editEntry(let entry): EditEntryView(entry: entry) { screen = .day }
                case .logWork(let item): LogWorkView(item: item) { screen = .day }
                }
            }
        }
        .frame(width: 500)
        // Every screen at its full height: the menu-bar window otherwise squeezed rows that may shrink
        // (a Log form's duration note ended up drawn over the next row).
        .fixedSize(horizontal: false, vertical: true)
        // Opaque like Harvest: reads cleanly over busy windows, unlike glass behind dense text.
        .background(.background)
        .tint(Brand.purple)
        .dropDestination(for: URL.self) { urls, _ in
            return startTask(from: urls)
        }
        // The popover keeps its content between opens: each open starts on today and reloads.
        .onReceive(NotificationCenter.default.publisher(for: StatusItem.willOpen)) { _ in
            screen = .day
            day = calendar.startOfDay(for: .now)
            opens += 1
        }
        .task(id: opens) {
            await store.refresh()
            await store.loadStarred()
            await store.refreshDueToday()
        }
        // Revalidates the (cached) week on every open (entries edited on the web), on week change, after anything
        // is logged, and once the user ID arrives (it can still be loading when the popover first opens after launch).
        .task(id: "\(opens)|\(week.start.timeIntervalSince1970)|\(store.logRevision)|\(store.userId ?? 0)") {
            await store.loadWeek(containing: day)
        }
    }

    // MARK: Day screen

    private var dayScreen: some View {
        VStack(spacing: 0) {
            header
            WeekStrip(week: week, selected: $day, totals: loggedTotals, liveToday: true)
            Divider()
            // Just below the week strip, over the list: every confirmed write lands back on this screen.
            dayList.overlay { ToastOverlay() }
            bottomBar
        }
        // Day navigation from the keyboard, as in Harvest.
        .background {
            Button("Previous Day") { shiftDay(-1) }.keyboardShortcut(.leftArrow, modifiers: []).hidden()
            Button("Next Day") { shiftDay(1) }.keyboardShortcut(.rightArrow, modifiers: []).hidden()
        }
    }

    private var header: some View {
        let title = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return ScreenHeader(title: isToday ? "Today: \(title)" : title) {
            if !isToday {
                Button("Today") { day = calendar.startOfDay(for: .now) }
                    .buttonStyle(PressStyle())
                    .font(.callout.weight(.medium))
                    .keyboardShortcut("t")
            } else if let target = store.target(in: calendar.dateInterval(of: .day, for: day)!) {
                TodayTotal(logged: loggedTotals[day] ?? 0, target: target)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    /// Logged minutes per day. Today's running timers are added by the views that show them
    /// (`TodayTotal`, the strip's today cell): reading the clock here re-rendered the whole popover every second.
    private var loggedTotals: [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for entry in weekEntries ?? [] {
            guard let logged = entry.timeLogged else { continue }
            totals[calendar.startOfDay(for: logged), default: 0] += TimeInterval(entry.minutes * 60)
        }
        return totals
    }

    private var entriesForDay: [TimeEntry] {
        (weekEntries ?? [])
            .filter { $0.timeLogged.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.timeLogged ?? .distantPast) < ($1.timeLogged ?? .distantPast) }
    }

    private var dayList: some View {
        let entries = entriesForDay
        let timers = isToday ? store.timers : []
        return ScrollView {
            VStack(spacing: 0) {
                // Labelled as in the window's Today page: a paused timer and a logged entry otherwise look alike.
                if !timers.isEmpty { SectionHeader("Timers") }
                ForEach(timers) { timer in
                    TimerRow(timer: timer, onLog: { screen = .log(timer) }, onEdit: { screen = .edit(timer) })
                    RowDivider()
                }
                if !entries.isEmpty {
                    SectionHeader("Logged", trailing: TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60).hoursMinutes)
                }
                ForEach(entries) { entry in
                    DayEntryRow(entry: entry, onStart: start) { screen = .editEntry(entry) }
                    RowDivider()
                }
                if timers.isEmpty && entries.isEmpty && weekEntries == nil {
                    ProgressView().controlSize(.small).padding(.vertical, Space.xxl + Space.m)
                } else if timers.isEmpty && entries.isEmpty {
                    VStack(spacing: Space.s) {
                        Text(isToday ? "Nothing tracked yet today" : "Nothing logged on this day")
                            .foregroundStyle(.secondary)
                        Button("Start a Timer") { screen = .newTimer }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.purpleFill)
                    }
                    .padding(.vertical, Space.xxl + Space.m)
                }
            }
        }
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bottomBar: some View {
        ActionBar {
            Button { screen = .newTimer } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                .buttonStyle(.borderedProminent)
                .tint(Brand.purpleFill)
                .keyboardShortcut("n")
                .help("New Timer (⌘N)")
                .accessibilityLabel("New Timer")
            Button { screen = .pinned } label: { Image(systemName: "pin").frame(width: 22, height: 20) }
                .help("Pinned")
                .accessibilityLabel("Pinned")
            Button { screen = .summary } label: { Image(systemName: "info").frame(width: 22, height: 20) }
                .help("Time Summary")
                .accessibilityLabel("Time Summary")
            if !store.timers.isEmpty {
                Button { screen = .logAll } label: {
                    Label(store.timers.count == 1 ? "Log Timer" : "Log All", systemImage: "checkmark")
                }
                .fixedSize() // never "Lo…" next to Open Window
                .help("Log timers to Teamwork")
            }
            Spacer()
            // Split button: click opens the main window; its arrow holds what the gear menu used to.
            Menu {
                if let site = store.webSite { Link("Open Teamwork in Browser", destination: site) }
                Button("Settings…", action: showSettings)
                Divider()
                Button("Quit Stint") { NSApp.terminate(nil) }
            } label: {
                Label("Open Window", systemImage: "macwindow")
            } primaryAction: {
                showWindow()
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Open the Stint window (⌘0)")
        }
        .background {
            // ⌘, ⌘0 ⌘Q and ⌘1–⌘9 (pinned) keep working without visible buttons.
            Button("Settings…", action: showSettings).keyboardShortcut(",").hidden()
            Button("Open Window", action: showWindow).keyboardShortcut("0").hidden()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q").hidden()
            ForEach(Array(store.pins.prefix(9).enumerated()), id: \.element.id) { index, item in
                Button(item.title) { Task { await store.start(item) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .hidden()
            }
        }
    }

    // MARK: Other screens

    private var signedOut: some View {
        VStack(spacing: 0) {
            ScreenHeader("Stint")
            VStack(spacing: Space.s) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Not signed in").font(.headline)
                Text("Connect your Teamwork site to start tracking.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xxl)
            ActionBar {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Sign In…") { show(.account) }.primaryAction()
            }
        }
    }

    // MARK: Actions

    private func start(_ item: WorkItem) {
        screen = .day
        day = calendar.startOfDay(for: .now)
        Task { await store.start(item) }
    }

    private func shiftDay(_ days: Int) {
        day = calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    private func showSettings() { show(.settings) }

    /// Opens the main window on a page (Settings and Account live there too).
    private func show(_ section: Store.Section) {
        store.section = section
        showWindow()
    }

    private func showWindow() {
        NSApp.activate()
        // The popover lives outside SwiftUI's scenes, so it opens the window through the store.
        store.openMainWindow?()
    }

    /// A Teamwork task link dropped on the popover starts a timer on that task, as in the old app.
    private func startTask(from urls: [URL]) -> Bool {
        guard let link = urls.first(where: { taskID(fromLink: $0.absoluteString) != nil }) else { return false }
        Task { if let item = await store.item(fromLink: link.absoluteString) { await store.start(item) } }
        return true
    }
}

/// Mon–Sun with each day's total; click a day to show it, arrows change week.
struct WeekStrip: View {
    let week: DateInterval
    @Binding var selected: Date
    let totals: [Date: TimeInterval]
    /// Adds today's running timers on the store's clock (the popover passes logged totals only).
    var liveToday = false

    var body: some View {
        let calendar = Calendar.current
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        HStack(spacing: 0) {
            // One day at a time (as ← → do); stepping past Monday or Sunday moves the strip to that week.
            // The whole 28×48 column takes the click, not just the glyph.
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 48).contentShape(.rect) }
                .help("Previous day")
                .accessibilityLabel("Previous day")
            ForEach(days, id: \.self) { day in
                DayCell(day: day, selected: $selected, logged: totals[calendar.startOfDay(for: day)] ?? 0,
                        live: liveToday && calendar.isDateInToday(day))
            }
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 48).contentShape(.rect) }
                .help("Next day")
                .accessibilityLabel("Next day")
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.m)
    }

    private func move(_ days: Int) {
        selected = Calendar.current.date(byAdding: .day, value: days, to: selected) ?? selected
    }
}

/// One day of the strip. Only a live cell reads the store's clock, so a running timer re-renders it alone.
private struct DayCell: View {
    @Environment(Store.self) private var store
    let day: Date
    @Binding var selected: Date
    let logged: TimeInterval
    let live: Bool
    @State private var hovering = false

    var body: some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let total = live ? logged + store.timers.reduce(0) { $0 + store.elapsed($1, at: store.menuBarNow) } : logged
        Button { selected = calendar.startOfDay(for: day) } label: {
            VStack(spacing: Space.xs) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : isToday ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.primary))
                    .frame(width: 34, height: 34)
                    // A faint circle under the pointer says the day is clickable; selection itself moves instantly
                    // (← → step through days many times a day).
                    .background(isSelected ? Brand.purpleFill : Brand.purple.opacity(hovering ? 0.1 : 0), in: .circle)
                    .animation(hovering ? nil : .easeOut(duration: 0.15), value: hovering)
                Text(total.hoursMinutes)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isSelected || isToday ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .onHover { hovering = $0 }
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(total.spoken)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Today's logged time plus running timers against the day target, on the store's clock.
/// A leaf, so each second re-renders this text rather than the popover around it.
struct TodayTotal: View {
    @Environment(Store.self) private var store
    let logged: TimeInterval
    let target: TimeInterval

    var body: some View {
        let total = logged + store.timers.reduce(0) { $0 + store.elapsed($1, at: store.menuBarNow) }
        Text("\(total.hoursMinutes) / \(target.hoursMinutes)")
            .accessibilityLabel("Today, \(total.spoken) of \(target.spoken)")
    }
}

/// Pinned items (⌘1–⌘9) and today's due tasks: the quick "repeat what I always do" list.
struct PinnedList: View {
    @Environment(Store.self) private var store
    let log: (WorkItem) -> Void
    let start: (WorkItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.pins.isEmpty {
                    Text("Right-click any task, project or timer and choose Pin to start it here in one click.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.l)
                } else {
                    SectionHeader("Pinned", trailing: "⌘1–⌘\(min(store.pins.count, 9))")
                    ForEach(Array(store.pins.enumerated()), id: \.element.id) { index, item in
                        WorkRow(item: item, shortcut: index < 9 ? index + 1 : nil, showsPin: false, log: { log(item) }) { start(item) }
                    }
                }
                let due = store.dueToday.filter { !store.isPinned($0) }
                if !due.isEmpty {
                    SectionHeader("Due Today")
                    ForEach(due) { item in WorkRow(item: item, log: { log(item) }) { start(item) } }
                }
            }
            .padding(.bottom, Space.s)
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A logged entry in the popover's day list: bold task, project and notes; duration and Start (restart).
/// An Edit icon appears under Start on hover, as on timer rows; double-click, the context menu and VoiceOver also edit.
struct DayEntryRow: View {
    @Environment(Store.self) private var store
    let entry: TimeEntry
    /// Starts a timer now and shows today, where it runs.
    let onStart: (WorkItem) -> Void
    let onEdit: () -> Void
    @State private var confirmingDelete = false
    @State private var confirmingStart: WorkItem?
    @State private var hovering = false

    var body: some View {
        let title = entry.taskId.flatMap(store.taskName) ?? entry.projectId.map(store.projectName) ?? "Time entry"
        if confirmingDelete {
            ConfirmRow(question: "Delete this entry from Teamwork?",
                       detail: "\(title) · \(TimeInterval(entry.minutes * 60).hoursMinutes)",
                       action: "Delete", cancel: { confirmingDelete = false }) {
                confirmingDelete = false
                Task { await store.deleteEntry(entry) }
            }
        } else if let item = confirmingStart {
            ConfirmRow(question: "Start a timer for today?", detail: title, action: "Start Today",
                       destructive: false, cancel: { confirmingStart = nil }) {
                confirmingStart = nil
                onStart(item)
            }
        } else {
            row
        }
    }

    /// Timers always run now, so starting from another day's entry asks first.
    private func start(_ item: WorkItem) {
        if Calendar.current.isDateInToday(entry.timeLogged ?? .now) { onStart(item) } else { confirmingStart = item }
    }

    private var row: some View {
        let task = entry.taskId.flatMap(store.taskName)
        let project = entry.projectId.map(store.projectName) ?? "No project"
        let item = entry.projectId.map {
            WorkItem(projectId: $0, projectName: project, taskId: entry.taskId, taskName: task,
                     description: entry.description, billable: entry.billable)
        }
        let title = task ?? project
        return HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                TitleLink(title: title, url: store.webURL(projectId: entry.projectId, taskId: entry.taskId))
                if task != nil { Text(project).foregroundStyle(.secondary).lineLimit(1) }
                if !entry.description.isEmpty {
                    Text(entry.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if entry.locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Locked")
                }
                Text(TimeInterval(entry.minutes * 60).hoursMinutes)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                // One column as wide as Start, so Edit spans it, as Edit and Log do on timer rows.
                VStack(spacing: Space.xs) {
                    if let item {
                        Button { start(item) } label: { Label("Start", systemImage: "clock") }
                            .buttonStyle(StartPauseStyle())
                            .help("Start a new timer on this task")
                    }
                    if !entry.locked {
                        Button(action: onEdit) { Label("Edit", systemImage: "square.and.pencil") }
                            .buttonStyle(RowIconStyle())
                            .help("Edit time, date or notes")
                            .accessibilityLabel("Edit \(title) entry")
                            // Space kept while hidden, so rows don't jump; VoiceOver edits through the row's actions.
                            .opacity(hovering ? 1 : 0)
                            .disabled(!hovering)
                            .accessibilityHidden(!hovering)
                            .animation(.easeOut(duration: 0.15), value: hovering)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !entry.locked { onEdit() } }
        .contextMenu {
            if let item { Button("Start Timer Again") { start(item) } }
            Button("Edit…", action: onEdit).disabled(entry.locked)
            if let item { Button(store.isPinned(item) ? "Unpin" : "Pin") { store.togglePin(item) } }
            if let url = store.webURL(projectId: entry.projectId, taskId: entry.taskId) {
                Link("Open in Teamwork", destination: url)
            }
            Divider()
            Button("Delete…", role: .destructive) { confirmingDelete = true }.disabled(entry.locked)
        }
        .accessibilityElement(children: .contain)
        // The context menu alone isn't reliably reachable with VoiceOver.
        .accessibilityActions {
            if !entry.locked {
                Button("Edit \(title) entry", action: onEdit)
                Button("Delete Entry") { confirmingDelete = true }
            }
        }
    }
}

/// Time Summary (from Harvest): today, yesterday, this week and this month, logged time plus running
/// timers, with progress toward the working-day target. A full popover screen, opaque like the rest.
struct TimeSummary: View {
    @Environment(Store.self) private var store
    let back: () -> Void
    let openWeek: () -> Void
    @State private var entries: [TimeEntry]?

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.dateInterval(of: .day, for: now)!
        let yesterday = DateInterval(start: today.start.addingTimeInterval(-86_400), end: today.start)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!
        let tracked = store.timers.reduce(0) { $0 + store.elapsed($1, at: store.menuBarNow) }
        VStack(spacing: 0) {
            ScreenHeader("Time Summary", back: back)
            HStack(alignment: .top, spacing: 0) {
                tile("Today", logged(in: today).map { $0 + tracked }, target: store.target(in: today))
                Divider()
                tile("Yesterday", logged(in: yesterday), target: store.target(in: yesterday), past: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                tile("This week", logged(in: week).map { $0 + tracked }, target: store.target(in: week))
                Divider()
                tile("This month", logged(in: month).map { $0 + tracked }, target: nil,
                     note: daysLogged(in: month).map { "Logged on \($0) day\($0 == 1 ? "" : "s")" })
            }
            .fixedSize(horizontal: false, vertical: true)
            ActionBar {
                Spacer()
                Button("Open This Week", action: openWeek)
                    .help("Show this week's entries in the main window")
            }
        }
        // Waits for the user ID (it can still be loading right after launch or sign-in).
        .task(id: store.userId) {
            let start = min(month.start, week.start, yesterday.start)
            entries = await store.timeEntries(from: start, to: today.end.addingTimeInterval(-1))
        }
    }

    /// One figure: small-caps label, large total, then progress toward the target or a note.
    /// `past`: the period is over, so a shortfall reads "under", not "left".
    private func tile(_ label: String, _ value: TimeInterval?, target: TimeInterval?, note: String? = nil,
                      past: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value?.hoursMinutes ?? "–")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
            if let target, let value {
                ProgressView(value: min(value / target, 1))
                    .progressViewStyle(.linear)
                    .tint(Brand.purpleFill)
                Text(value >= target ? "Target met"
                     : "\((target - value).hoursMinutes) \(past ? "under" : "left of") \(target.hoursMinutes)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(value >= target ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.secondary))
            } else if let note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(label, value, target))
    }

    private func accessibilityText(_ label: String, _ value: TimeInterval?, _ target: TimeInterval?) -> String {
        guard let value else { return "\(label), loading" }
        guard let target else { return "\(label), \(value.spoken)" }
        return "\(label), \(value.spoken) of \(target.spoken)"
    }

    /// Logged seconds in an interval; nil until loaded.
    private func logged(in interval: DateInterval) -> TimeInterval? {
        entries.map { list in
            TimeInterval(list.filter { $0.timeLogged.map(interval.contains) ?? false }.reduce(0) { $0 + $1.minutes } * 60)
        }
    }

    private func daysLogged(in interval: DateInterval) -> Int? {
        entries.map { list in
            Set(list.compactMap { $0.timeLogged }.filter(interval.contains).map { Calendar.current.startOfDay(for: $0) }).count
        }
    }
}
