import SwiftUI

/// Library + detail window for reviewing and editing. Daily start/stop lives in the menu bar.
struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List {
                Section("Time") {
                    SidebarRow(section: .timers, trailing: store.timers.isEmpty ? nil : "\(store.timers.count)")
                    SidebarRow(section: .today)
                    SidebarRow(section: .week)
                    SidebarRow(section: .month)
                }
                Section("Work") {
                    SidebarRow(section: .pinned, trailing: store.pins.isEmpty ? nil : "\(store.pins.count)")
                    SidebarRow(section: .starred)
                    SidebarRow(section: .tasks)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240) // room for the footer's site name
        } detail: {
            Group {
                let section = store.section ?? .timers
                if section == .settings {
                    GeneralSettings().navigationTitle("Settings")
                } else if section == .account {
                    AccountSettings().navigationTitle("Account")
                } else if !store.isSignedIn {
                    ContentUnavailableView {
                        Label("Not Signed In", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("Connect your Teamwork site to see your timers.")
                    } actions: {
                        Button("Sign In…") { store.section = .account }.primaryAction()
                    }
                } else {
                    switch section {
                    case .timers: TimersView()
                    case .today: EntriesView(span: .day)
                    case .week: EntriesView(span: .weekOfYear)
                    case .month: EntriesView(span: .month)
                    case .pinned: PinnedView()
                    case .starred: StarredView()
                    case .tasks: MyTasksView()
                    case .settings, .account: EmptyView() // handled above
                    }
                }
            }
            .frame(minWidth: 420)
            // Bottom of the page, clear of each page's own top bar (the Today week strip, toolbars).
            .overlay { ToastOverlay(edge: .bottom) }
            .safeAreaInset(edge: .bottom) {
                ErrorBanner().background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Timer", systemImage: "plus") { store.showingNewTimer = true }
                    .help("New Timer (⌘N)")
                    .disabled(!store.isSignedIn)
            }
        }
        .sheet(isPresented: $store.showingNewTimer) { NewTimerSheet() }
        .sheet(isPresented: $store.showingLogAll) {
            LogAllView { store.showingLogAll = false }
                .frame(width: 460) // no padding: the header band runs edge to edge, as in every sheet
        }
        // Drop a Teamwork task link anywhere in the window to start a timer on it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let link = urls.first(where: { taskID(fromLink: $0.absoluteString) != nil }) else { return false }
            Task { if let item = await store.item(fromLink: link.absoluteString) { await store.start(item) } }
            return true
        }
        // The app is a menu-bar app; it gets a Dock icon and menu bar only while this window is open.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate() // after the policy change, or the app's menu bar doesn't show
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Sidebar item with our own selection: List(selection:) paints the system accent (blue), which the
/// app can't change without an Xcode-built asset catalog. ⌘1–⌘6 and ⌘, (menus) select from the keyboard.
struct SidebarRow: View {
    @Environment(Store.self) private var store
    let section: Store.Section
    /// A count at the trailing edge (timers, pins).
    var trailing: String?

    var body: some View {
        let selected = (store.section ?? .timers) == section
        Button { store.section = section } label: {
            HStack {
                Label {
                    Text(section.rawValue).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                } icon: {
                    Image(systemName: section.symbol).foregroundStyle(Brand.purple)
                }
                Spacer(minLength: Space.xs)
                if let trailing { Text(trailing).monospacedDigit().foregroundStyle(.secondary) }
            }
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xxs)
            .background(Brand.purple.opacity(selected ? 0.14 : 0), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pinned to the sidebar's bottom: who's signed in (opens Account) and a Settings gear.
struct SidebarFooter: View {
    @Environment(Store.self) private var store

    var body: some View {
        let section = store.section
        HStack(spacing: Space.xxs) {
            Button { store.section = .account } label: {
                HStack(spacing: Space.xs) {
                    Avatar(name: store.accountName)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.isSignedIn ? store.accountName ?? "Account" : "Sign In")
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if store.isSignedIn, let host = store.site?.host() {
                            Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.xs)
                .padding(.vertical, Space.xs - 2)
                .background(Brand.purple.opacity(section == .account ? 0.14 : 0), in: .rect(cornerRadius: 8))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Account")
            .accessibilityAddTraits(section == .account ? .isSelected : [])

            Button { store.section = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(section == .settings ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.secondary))
                    .frame(width: 30, height: 30)
                    .background(Brand.purple.opacity(section == .settings ? 0.14 : 0), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(section == .settings ? .isSelected : [])
        }
        .padding(.horizontal, Space.xs)
        .padding(.bottom, Space.s)
    }
}

/// Initials in a brand-purple circle; a person glyph when signed out.
struct Avatar: View {
    let name: String?

    var body: some View {
        let initials = (name ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        ZStack {
            Circle().fill(Brand.purpleFill)
            if initials.isEmpty {
                Image(systemName: "person.fill").font(.callout)
            } else {
                Text(initials.uppercased()).font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct NewTimerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("New Timer") { dismiss() }
            WorkPicker(maxHeight: 420) { item in
                dismiss()
                Task { await store.start(item) }
            }
        }
        .frame(width: 440)
    }
}

/// In place of a page's rows when its first load failed: says so and retries. The reason is in the error banner.
struct LoadFailed: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Teamwork couldn't be reached. Check your connection and try again.")
        } actions: {
            Button("Try Again", action: retry)
        }
    }
}

/// A main-window page in the popover's language: full-width rows, inset dividers, small-caps headers
/// that stay pinned while scrolling.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) { content }
                .padding(.bottom, Space.l)
        }
    }
}

/// Which form a timer row opened.
enum TimerSheet: Identifiable {
    case log(TWTimer), edit(TWTimer)
    var id: String {
        switch self {
        case .log(let timer): "log-\(timer.id)"
        case .edit(let timer): "edit-\(timer.id)"
        }
    }
}

/// Timer rows for Timers and Today; the owning list presents the sheet once (see `timerSheet`).
struct TimerList: View {
    let timers: [TWTimer]
    @Binding var sheet: TimerSheet?

    var body: some View {
        ForEach(timers) { timer in
            TimerRow(timer: timer, onLog: { sheet = .log(timer) }, onEdit: { sheet = .edit(timer) })
            RowDivider()
        }
    }
}

extension View {
    /// On the page, not the ForEach: modifiers on a ForEach apply to every row.
    func timerSheet(_ sheet: Binding<TimerSheet?>) -> some View {
        self.sheet(item: sheet) { which in
            Group {
                switch which {
                case .log(let timer): LogView(timer: timer) { sheet.wrappedValue = nil }
                case .edit(let timer): EditTimerView(timer: timer) { sheet.wrappedValue = nil }
                }
            }
            .frame(width: 440)
        }
    }
}

struct TimersView: View {
    @Environment(Store.self) private var store
    @State private var sheet: TimerSheet?
    /// Typed in the toolbar's filter field.
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    private var filter: String { query.trimmingCharacters(in: .whitespaces) }
    /// The timers listed: all of them, or those whose task, project or notes match the filter.
    private var shown: [TWTimer] {
        store.timers.filter { timer in
            matchesFilter(filter, fields: [timer.taskId.flatMap(store.taskName), timer.projectId.map(store.projectName),
                                           timer.description].compactMap { $0 })
        }
    }

    var body: some View {
        let count = "\(store.timers.count) timer\(store.timers.count == 1 ? "" : "s")"
        Page { TimerList(timers: shown, sheet: $sheet) }
            .timerSheet($sheet)
            .overlay {
                if store.timers.isEmpty {
                    ContentUnavailableView("No Timers", systemImage: "timer",
                                           description: Text("Start one with ⌘N or from the menu bar, or drop a Teamwork task link here. Timers started on the web show up too."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            .glidingRows(store.timers.map(\.id)) // after the overlay, so "No Timers" fades in with the last row out
            .navigationTitle("Timers")
            .navigationSubtitle(store.timers.isEmpty ? "" : filter.isEmpty ? count : "\(shown.count) of \(count)")
            .entryFilter($query, focused: $filterFocused)
            .toolbar {
                ToolbarItem {
                    Button("Log All…", systemImage: "checkmark.circle") { store.showingLogAll = true }
                        .help("Log all timers at once")
                        .disabled(store.timers.isEmpty)
                }
            }
            .refreshable { await store.refresh() }
    }
}

/// Logged time for a day (with the popover's week strip), a week or a month, grouped by day with totals.
struct EntriesView: View {
    @Environment(Store.self) private var store
    let span: Calendar.Component
    @State private var anchor = Calendar.current.startOfDay(for: .now)
    @State private var sheet: TimerSheet?
    @State private var editingEntry: TimeEntry?
    @State private var position = ScrollPosition(idType: Date.self)
    /// Typed in the toolbar's filter field.
    @State private var query = ""
    @FocusState private var filterFocused: Bool
    /// The weeks in view couldn't be fetched and none were cached: the page offers a retry instead of a spinner.
    @State private var loadFailed = false
    /// The day this page last took for today, so it can follow the date past midnight.
    @State private var today = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }
    private var interval: DateInterval { calendar.dateInterval(of: span, for: anchor)! }
    private var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: anchor)! }
    private var isCurrent: Bool { interval.contains(.now) }
    /// The weeks in view: the one for a day or a week, four to six for a month.
    private var weeks: [DateInterval] { weekIntervals(covering: interval) }
    /// nil until every week in view has loaded once (then cached in the store).
    private var weekEntries: [TimeEntry]? {
        let cached = weeks.map { store.weeks[$0.start] }
        return cached.contains { $0 == nil } ? nil : cached.flatMap { $0! }
    }
    private var entries: [TimeEntry] { (weekEntries ?? []).filter { $0.timeLogged.map(interval.holds) ?? false } }
    private var total: TimeInterval { TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60) }
    /// Working hours in view; nil on days off. None for a month, as in Time Summary: Teamwork's working hours
    /// don't know holidays or time off, so a month's target overstates it.
    private var target: TimeInterval? { span == .month ? nil : store.target(in: interval) }
    /// No entries and, in the current period, no timers either.
    private var isEmpty: Bool { entries.isEmpty && !(isCurrent && !store.timers.isEmpty) }

    private var filter: String { query.trimmingCharacters(in: .whitespaces) }
    private var filtering: Bool { !filter.isEmpty }
    /// The entries listed: all of them, or those whose task, project or notes match the filter.
    private var shown: [TimeEntry] {
        guard filtering else { return entries }
        return entries.filter { entry in
            matchesFilter(filter, fields: [entry.taskId.flatMap(store.taskName), entry.projectId.map(store.projectName),
                                           entry.description].compactMap { $0 })
        }
    }

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: shown) { calendar.startOfDay(for: $0.timeLogged ?? interval.start) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { ($0.timeLogged ?? .distantPast) < ($1.timeLogged ?? .distantPast) }) }
    }

    /// Logged minutes per day for the week strip; its today cell adds the timers on the store's clock (as in the popover).
    private var dayTotals: [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for entry in weekEntries ?? [] {
            guard let logged = entry.timeLogged else { continue }
            totals[calendar.startOfDay(for: logged), default: 0] += TimeInterval(entry.minutes * 60)
        }
        return totals
    }

    var body: some View {
        Page {
            if span == .weekOfYear {
                if weekEntries != nil && !isEmpty && !filtering {
                    WeekChart(week: interval, entries: entries) { day in
                        withAnimation { position.scrollTo(id: day, anchor: .top) }
                    }
                    PeriodSummary(entries: entries, target: target, live: isCurrent, past: interval.end <= .now)
                }
            } else if span == .month {
                if weekEntries != nil && !isEmpty && !filtering {
                    MonthWeeks(month: interval, entries: entries) { day in
                        withAnimation { position.scrollTo(id: day, anchor: .top) }
                    }
                }
            } else if !filtering, target != nil || !isEmpty {
                PeriodSummary(entries: entries, target: target, live: isCurrent, past: interval.end <= .now)
            }
            if isCurrent && !store.timers.isEmpty && !filtering {
                Section { TimerList(timers: store.timers, sheet: $sheet) } header: { SectionHeader("Timers") }
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        DayEntryRow(entry: entry, onStart: start) { editingEntry = entry }
                        RowDivider()
                    }
                } header: {
                    let logged = TimeInterval(group.entries.reduce(0) { $0 + $1.minutes } * 60)
                    let goal = store.target(in: calendar.dateInterval(of: .day, for: group.day)!)
                    // Filtered, the day's target says nothing about the matches: only their time.
                    SectionHeader(group.day.formatted(.dateTime.weekday(.wide).month().day()),
                                  trailing: filtering ? logged.hoursMinutes
                                      : goal.map { "\(logged.hoursMinutes) / \($0.hoursMinutes)" } ?? logged.hoursMinutes)
                }
            }
        }
        .scrollPosition($position) // the week chart and the month's weeks scroll to a clicked day
        .safeAreaInset(edge: .top, spacing: 0) {
            if span == .day {
                VStack(spacing: 0) {
                    WeekStrip(week: week, selected: $anchor, totals: dayTotals, liveToday: true)
                    Divider()
                }
                .background(.background)
            }
        }
        .timerSheet($sheet)
        .sheet(item: $editingEntry) { entry in
            EditEntryView(entry: entry) { editingEntry = nil }
                .frame(width: 440)
        }
        .overlay {
            if weekEntries == nil {
                if loadFailed {
                    LoadFailed { Task { await load() } }
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if filtering && shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else if isEmpty {
                ContentUnavailableView("Nothing Logged", systemImage: "clock", description: Text("Time you log shows up here."))
            }
        }
        // A week that arrives from the network fades in over the spinner. Leaving a week (⌘[ ⌘]) and cached
        // weeks stay instant: keyboard steps shouldn't wait on a fade.
        .animation(weekEntries == nil ? nil : .easeOut(duration: 0.2), value: weekEntries == nil)
        // Timers only: entries also change on ⌘[ ⌘] steps, which stay instant.
        .glidingRows(store.timers.map(\.id))
        .navigationTitle(title)
        .entryFilter($query, focused: $filterFocused)
        .background {
            if filtering {
                // "3 of 41 entries · 4:15": how much of the period the filter found.
                let matched = TimeInterval(shown.reduce(0) { $0 + $1.minutes } * 60)
                Color.clear.navigationSubtitle(
                    "\(shown.count) of \(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(matched.hoursMinutes)")
            } else {
                EntriesSubtitle(logged: total, target: target, live: span == .day && isCurrent)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                    .keyboardShortcut("[")
                    .help("Previous \(unit) (⌘[)")
                Button("Today") { anchor = calendar.startOfDay(for: .now) }
                    .keyboardShortcut("t")
                    .disabled(isCurrent)
                    .help("Go to Today (⌘T)")
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .keyboardShortcut("]")
                    .help("Next \(unit) (⌘])")
            }
        }
        // Revalidates the (cached) weeks on week or month change, after anything is logged (here or from the
        // popover), and once the user ID arrives.
        .task(id: "\(weeks[0].start.timeIntervalSince1970)|\(store.logRevision)|\(store.userId ?? 0)") { await load() }
        .refreshable { await load() }
        // Back from the browser: entries edited on the web show up. And after midnight, "Today" is today again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            followToday()
            Task { await load() }
        }
    }

    private var title: String {
        if span == .day { return isCurrent ? "Today" : anchor.formatted(.dateTime.weekday(.wide).month().day()) }
        if span == .month { return isCurrent ? "This Month" : anchor.formatted(.dateTime.month(.wide).year()) }
        if isCurrent { return "This Week" }
        return "Week of \(interval.start.formatted(.dateTime.month().day()))"
    }

    private var unit: String { span == .day ? "Day" : span == .month ? "Month" : "Week" }

    /// A day or a week also loads the weeks either side; a month loads its own.
    private func load() async {
        let asked = weeks.map(\.start)
        loadFailed = false
        if span == .month { await store.loadWeeks(covering: interval) } else { await store.loadWeek(containing: anchor) }
        // Still nothing once the load ran its course (not one cut short by stepping to another period): Teamwork
        // couldn't be reached. Without a user ID nothing was asked; the load runs again when it arrives.
        if !Task.isCancelled, asked == weeks.map(\.start) { loadFailed = weekEntries == nil && store.userId != nil }
    }

    /// Left open overnight on the current day, week or month, the page moves on with the date the next time Stint
    /// comes forward, so "Today" isn't yesterday. A page stepped back to an earlier period stays where it is.
    // ponytail: on activation only; a window kept frontmost across midnight waits for the next activation.
    private func followToday() {
        let now = calendar.startOfDay(for: .now)
        guard now != today else { return }
        if interval.holds(today) { anchor = now }
        today = now
    }

    private func step(_ direction: Int) {
        anchor = calendar.date(byAdding: span, value: direction, to: anchor) ?? anchor
    }

    private func start(_ item: WorkItem) {
        anchor = calendar.startOfDay(for: .now)
        Task { await store.start(item) }
    }
}

private extension View {
    /// The toolbar's filter field, on every page with a list; ⌘F puts the cursor in it and Esc clears it.
    func entryFilter(_ text: Binding<String>, focused: FocusState<Bool>.Binding,
                     prompt: String = "Filter by task, project or notes") -> some View {
        searchable(text: text, prompt: Text(prompt))
            .searchFocused(focused)
            .background {
                Button("Filter") { focused.wrappedValue = true }.keyboardShortcut("f").hidden()
            }
    }
}

/// Today's timers on the store's clock; 0 elsewhere.
@MainActor private func tracked(_ store: Store, live: Bool) -> TimeInterval {
    live ? store.timers.reduce(0) { $0 + store.elapsed($1, at: store.menuBarNow) } : 0
}

/// The window subtitle: logged time against the target and, today, the timers' time and the sum the week strip shows.
/// A leaf set from the page's background, so each clock tick re-renders it rather than the page.
private struct EntriesSubtitle: View {
    @Environment(Store.self) private var store
    let logged: TimeInterval
    let target: TimeInterval?
    let live: Bool

    var body: some View {
        let goal = target.map { " of \($0.hoursMinutes)" } ?? ""
        let timers = tracked(store, live: live)
        Color.clear.navigationSubtitle(live && !store.timers.isEmpty
            ? "Logged \(logged.hoursMinutes) · Timers \(timers.hoursMinutes) · \((logged + timers).hoursMinutes)\(goal)"
            : "Logged \(logged.hoursMinutes)\(goal)")
    }
}

/// Today's and This Week's bottom line: the time against the target as a bar (billable, non-billable, then the
/// timers) over the same `TotalRow` as This Month. A day or week without a target gets the row alone. A leaf,
/// like `EntriesSubtitle`.
private struct PeriodSummary: View {
    @Environment(Store.self) private var store
    let entries: [TimeEntry]
    let target: TimeInterval?
    let live: Bool
    /// The period is over, so a shortfall reads "under", not "left" (as in Time Summary).
    let past: Bool

    var body: some View {
        let logged = TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60)
        let billable = TimeInterval(entries.filter(\.billable).reduce(0) { $0 + $1.minutes } * 60)
        let timers = tracked(store, live: live)
        let total = logged + timers
        VStack(spacing: Space.xs) {
            if let target { TargetBar(logged: logged, nonBillable: logged - billable, timers: timers, target: target) }
            TotalRow(logged: logged, billable: billable, timers: timers, target: target)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .help(target.map { total >= $0 ? "Target met" : "\(($0 - total).hoursMinutes) \(past ? "under" : "left of") \($0.hoursMinutes)" } ?? "")
    }
}

/// A period's bottom line, the same on Today, This Week and This Month: "Total", what it's made of (billable with its
/// share, non-billable, the timers; these double as the key to the bars' colours) and the sum, against the target
/// when the period has one. `labels` and `figures` are other rows' to line up with (This Month's weeks).
private struct TotalRow: View {
    let logged: TimeInterval
    let billable: TimeInterval
    let timers: TimeInterval
    var target: TimeInterval?
    var labels: [String] = []
    var figures: [String] = []

    var body: some View {
        let total = logged + timers
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("Total").fontWeight(.semibold).sized(to: labels, alignment: .leading)
            // One line while it fits, else a key per line, so a narrow window doesn't clip it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) { keys }
                VStack(alignment: .leading, spacing: Space.xxs) { keys }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            metMark.opacity(target.map { total >= $0 } ?? false ? 1 : 0)
            targetFigure(total, of: target).fontWeight(.semibold).sized(to: figures, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var keys: some View {
        progressKey("Billable", billable, Brand.purpleFill,
                    detail: logged > 0 ? (billable / logged).formatted(.percent.precision(.fractionLength(0))) : nil)
        progressKey("Non-billable", logged - billable, TargetBar.nonBillableTint)
        if timers > 0 { progressKey("Timers", timers, TargetBar.timersTint) }
    }
}

/// After a total that reached its target; hidden, it keeps the figures in line.
private var metMark: some View {
    Image(systemName: "checkmark")
        .font(.caption.weight(.bold))
        .foregroundStyle(Brand.purple)
        .accessibilityHidden(true)
}

/// "34:10 / 40:00", or the time alone without a target. Met: all in purple. Otherwise the time stands out from
/// its target.
private func targetFigure(_ total: TimeInterval, of target: TimeInterval?) -> Text {
    guard let target else { return Text(total.hoursMinutes) }
    if total >= target { return Text("\(total.hoursMinutes) / \(target.hoursMinutes)").foregroundStyle(Brand.purple) }
    return Text("\(Text(total.hoursMinutes).foregroundStyle(.primary)) / \(target.hoursMinutes)").foregroundStyle(.secondary)
}

/// Logged time against a target as one capsule: logged solid, timers after it in a lighter tint. With `nonBillable`
/// (part of `logged`), the logged part splits into billable purple and non-billable grey.
private struct TargetBar: View {
    let logged: TimeInterval
    var nonBillable: TimeInterval = 0
    let timers: TimeInterval
    let target: TimeInterval
    static let timersTint = Brand.purple.opacity(0.4)
    /// Opaque, so it doesn't take on the timers' tint it's drawn over.
    static let nonBillableTint = Color(nsColor: .systemGray)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Each capsule runs under the one before it, so they read as one bar with lighter parts at its end.
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Self.timersTint).frame(width: width * min((logged + timers) / target, 1))
                if nonBillable > 0 {
                    Capsule().fill(Self.nonBillableTint).frame(width: width * min(logged / target, 1))
                }
                Capsule().fill(Brand.purpleFill).frame(width: width * min((logged - nonBillable) / target, 1))
            }
        }
        .frame(height: 8)
    }
}

/// A dot in the segment's colour, its name and its time, then an optional `detail` (a share).
private func progressKey(_ label: String, _ value: TimeInterval, _ color: Color, detail: String? = nil) -> some View {
    HStack(spacing: Space.xxs) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(label).foregroundStyle(.secondary)
        Text(value.hoursMinutes).fontWeight(.medium)
        if let detail { Text(detail).foregroundStyle(.secondary) }
    }
}

/// This Month's weeks, a row each: logged time against the week's target, billable and non-billable, with the
/// timers in the current week. Weeks are cut to the month, like the list below, so a week split by the month's
/// edge counts only its days in the month. Click a week to jump to its latest entries. A total row sums them, its
/// breakdown doubling as the bars' key (`TotalRow`, as on Today and This Week). A leaf, like `PeriodSummary`.
private struct MonthWeeks: View {
    @Environment(Store.self) private var store
    let month: DateInterval
    let entries: [TimeEntry]
    /// The latest day with entries in a clicked week.
    let select: (Date) -> Void

    private struct Week: Identifiable {
        let span: DateInterval
        let label: String
        let spoken: String
        let logged: TimeInterval
        let billable: TimeInterval
        let timers: TimeInterval
        let target: TimeInterval?
        let latest: Date?
        let isCurrent: Bool
        let isFuture: Bool
        var id: Date { span.start }
        var total: TimeInterval { logged + timers }
        var nonBillable: TimeInterval { logged - billable }
        var met: Bool { target.map { total >= $0 } ?? false }
        /// "34:10 / 40:00"; blank for a week still to come.
        var figure: String {
            if isFuture { return "" }
            return target.map { "\(total.hoursMinutes) / \($0.hoursMinutes)" } ?? total.hoursMinutes
        }
    }

    var body: some View {
        let weeks = weeks(now: .now)
        let logged = weeks.reduce(0) { $0 + $1.logged }
        let billable = weeks.reduce(0) { $0 + $1.billable }
        let timers = weeks.reduce(0) { $0 + $1.timers }
        let labels = weeks.map(\.label) + ["Total"]
        let figures = weeks.map(\.figure) + [(logged + timers).hoursMinutes]
        VStack(spacing: 0) {
            ForEach(weeks) { week in row(week, labels: labels, figures: figures) }
            RowDivider().padding(.vertical, Space.xxs)
            TotalRow(logged: logged, billable: billable, timers: timers, labels: labels, figures: figures)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.xxs + 2)
        }
        .padding(.top, Space.s)
    }

    private func weeks(now: Date) -> [Week] {
        let calendar = Calendar.current
        let interval = Date.IntervalFormatStyle.interval.day()
        return weekIntervals(covering: month).compactMap { $0.intersection(with: month) }.map { span in
            let inWeek = entries.filter { $0.timeLogged.map(span.holds) ?? false }
            let days = span.start..<calendar.date(byAdding: .day, value: -1, to: span.end)!
            let isCurrent = span.start <= now && now < span.end
            return Week(span: span,
                        label: days.formatted(interval.month(.abbreviated)),
                        spoken: days.formatted(interval.month(.wide)),
                        logged: TimeInterval(inWeek.reduce(0) { $0 + $1.minutes } * 60),
                        billable: TimeInterval(inWeek.filter(\.billable).reduce(0) { $0 + $1.minutes } * 60),
                        timers: tracked(store, live: isCurrent),
                        target: store.target(in: span),
                        latest: inWeek.compactMap(\.timeLogged).max().map(calendar.startOfDay),
                        isCurrent: isCurrent, isFuture: span.start > now)
        }
    }

    private func row(_ week: Week, labels: [String], figures: [String]) -> some View {
        Button { if let day = week.latest { select(day) } } label: {
            HStack(spacing: Space.s) {
                Text(week.label)
                    .fontWeight(week.isCurrent ? .semibold : .regular)
                    .foregroundStyle(week.isFuture ? AnyShapeStyle(.tertiary)
                                     : week.isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .sized(to: labels, alignment: .leading)
                if let target = week.target {
                    TargetBar(logged: week.logged, nonBillable: week.nonBillable, timers: week.timers, target: target)
                } else {
                    Spacer()
                }
                metMark.opacity(week.met ? 1 : 0)
                figure(week).sized(to: figures, alignment: .trailing)
            }
            .font(.callout)
            .monospacedDigit()
        }
        .buttonStyle(RowStyle(dense: true))
        .disabled(week.latest == nil)
        .help(week.logged > 0 ? "Billable \(week.billable.hoursMinutes) · Non-billable \(week.nonBillable.hoursMinutes)" : "")
        .accessibilityLabel(week.spoken)
        .accessibilityValue(spokenValue(week))
    }

    /// Blank for a week still to come.
    private func figure(_ week: Week) -> Text {
        week.isFuture ? Text("") : targetFigure(week.total, of: week.target)
    }

    private func spokenValue(_ week: Week) -> String {
        if week.isFuture { return week.target.map { "to come, target \($0.spoken)" } ?? "to come" }
        var parts = [week.logged > 0 ? "\(week.logged.spoken) logged, \(week.billable.spoken) billable" : "nothing logged"]
        if week.timers > 0 { parts.append("\(week.timers.spoken) in timers") }
        if let target = week.target { parts.append(week.met ? "target of \(target.spoken) met" : "target \(target.spoken)") }
        return parts.joined(separator: ", ")
    }
}

private extension View {
    /// As wide as the widest of `strings`, so a column lines up from row to row without fixing a width. Measured
    /// in semibold, the current week's weight, so its label doesn't push its bar out of line.
    func sized(to strings: [String], alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            ForEach(strings.indices, id: \.self) { Text(strings[$0]).fontWeight(.semibold).hidden() }
            self
        }
    }
}

struct PinnedView: View {
    @Environment(Store.self) private var store
    @State private var logging: WorkItem?
    /// Typed in the toolbar's filter field.
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        let filter = query.trimmingCharacters(in: .whitespaces)
        // With their places among all the pins, so a drop lands in the right slot while filtered.
        let shown = Array(store.pins.enumerated()).filter { matchesFilter(filter, fields: $0.element.filterFields) }
        Page {
            ForEach(shown, id: \.element.id) { index, item in
                WorkRow(item: item, showsPin: false, startButton: true, log: { logging = item }) {
                    Task { await store.start(item) }
                }
                    .draggable(item.id)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let from = store.pins.firstIndex(where: { $0.id == ids.first }) else { return false }
                        store.movePins(from: [from], to: index > from ? index + 1 : index)
                        return true
                    }
                RowDivider()
            }
        }
        .overlay {
            if store.pins.isEmpty {
                ContentUnavailableView("No Pins", systemImage: "pin",
                                       description: Text("Right-click a task, project or timer and choose Pin to start it in one click."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .glidingRows(store.pins.map(\.id)) // a dropped pin glides to its slot, its neighbours make room
        .sheet(item: $logging) { item in
            LogWorkView(item: item) { logging = nil }
                .frame(width: 440)
        }
        .navigationTitle("Pinned")
        .navigationSubtitle(filter.isEmpty ? "Drag to reorder. The first nine start with ⌘1–⌘9 in the menu bar."
                                           : "\(shown.count) of \(store.pins.count) pin\(store.pins.count == 1 ? "" : "s")")
        .entryFilter($query, focused: $filterFocused)
    }
}

/// Your starred projects, each with this week's logged time on it: a bar in This Month's colours (billable purple,
/// non-billable grey) against the busiest project, so the week's spread reads at a glance while the order stays
/// alphabetical. Projects with nothing this week stay bare.
struct StarredView: View {
    @Environment(Store.self) private var store
    /// Typed in the toolbar's filter field.
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        @Bindable var store = store
        let week = weekTotals()
        let busiest = week.values.map(\.logged).max() ?? 0
        let filter = query.trimmingCharacters(in: .whitespaces)
        let shown = store.starred.filter { matchesFilter(filter, fields: [$0.name]) }
        NavigationStack(path: $store.starredPath) {
            Page {
                ForEach(shown) { project in
                    ProjectRow(project: project, open: { store.starredPath.append(project) },
                               start: { Task { await store.start(WorkItem(project: project)) } }) {
                        if let time = week[project.id] {
                            TargetBar(logged: time.logged, nonBillable: time.logged - time.billable, timers: 0, target: busiest)
                                .frame(width: 96)
                                .help("Billable \(time.billable.hoursMinutes) · Non-billable \((time.logged - time.billable).hoursMinutes)")
                            Text(time.logged.hoursMinutes)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .frame(minWidth: 44, alignment: .trailing)
                                .accessibilityLabel("\(time.logged.spoken) this week")
                        }
                    }
                    RowDivider()
                }
            }
            .overlay {
                if store.starred.isEmpty {
                    ContentUnavailableView("No Starred Projects", systemImage: "star",
                                           description: Text("Star projects in Teamwork and they appear here and first in every picker."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            .navigationTitle("Starred Projects")
            .navigationSubtitle(store.starred.isEmpty ? "" : filter.isEmpty ? weekSubtitle(week)
                : "\(shown.count) of \(store.starred.count) project\(store.starred.count == 1 ? "" : "s")")
            .entryFilter($query, focused: $filterFocused, prompt: "Filter projects")
            .navigationDestination(for: Project.self) { ProjectTasks(project: $0) }
        }
        .task(id: "\(store.logRevision)|\(store.userId ?? 0)") {
            await store.loadStarred()
            await store.loadWeek(containing: .now)
        }
    }

    /// This week's logged time per starred project, from the week cache Today and the popover share.
    private func weekTotals() -> [Int: (logged: TimeInterval, billable: TimeInterval)] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        let starred = Set(store.starred.map(\.id))
        var totals: [Int: (logged: TimeInterval, billable: TimeInterval)] = [:]
        for entry in store.weeks[week.start] ?? [] {
            guard let id = entry.projectId, starred.contains(id), entry.minutes > 0 else { continue }
            let seconds = TimeInterval(entry.minutes * 60)
            totals[id, default: (0, 0)].logged += seconds
            if entry.billable { totals[id, default: (0, 0)].billable += seconds }
        }
        return totals
    }

    private func weekSubtitle(_ week: [Int: (logged: TimeInterval, billable: TimeInterval)]) -> String {
        let total = week.values.reduce(0) { $0 + $1.logged }
        return total > 0 ? "\(total.hoursMinutes) on these projects this week" : "Nothing logged on these projects this week"
    }
}

/// A project's tasks, the whole project first; the toolbar field searches them.
struct ProjectTasks: View {
    @Environment(Store.self) private var store
    let project: Project
    @State private var query = ""
    @State private var items: [WorkItem]?

    var body: some View {
        let whole = items?.filter { $0.taskId == nil } ?? []
        let tasks = items?.filter { $0.taskId != nil } ?? []
        Page {
            if !whole.isEmpty {
                Section { rows(whole) } header: { SectionHeader("Project") }
            }
            if !tasks.isEmpty {
                Section { rows(tasks) } header: { SectionHeader("Tasks") }
            }
        }
        .overlay {
            if items == nil {
                ProgressView().controlSize(.small)
            } else if whole.isEmpty && tasks.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle(project.name)
        .searchable(text: $query, prompt: "Search \(project.name)")
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            items = await store.search(query, in: project)
        }
    }

    private func rows(_ items: [WorkItem]) -> some View {
        ForEach(items) { item in
            WorkRow(item: item, showsProject: false, startButton: true) { Task { await store.start(item) } }
            RowDivider()
        }
    }
}

/// Tasks assigned to you, under a header per project (the rows then name their task list), each with its due date.
struct MyTasksView: View {
    @Environment(Store.self) private var store
    @AppStorage("myTasksFilter") private var filter = TeamworkClient.TaskFilter.today
    @State private var items: [AssignedTask] = []
    /// True from the start: false showed "No Tasks" for a frame before the first load began.
    @State private var loading = true
    /// The filter `items` were fetched for, so one filter's tasks never sit under another's tab.
    @State private var shownFilter: TeamworkClient.TaskFilter?
    /// The last load failed with nothing to show: the page offers a retry rather than "No Tasks".
    @State private var failed = false
    /// Typed in the toolbar's filter field (`filter` is the Today / Overdue / … picker).
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    private var typed: String { query.trimmingCharacters(in: .whitespaces) }
    /// The tasks listed: all of them, or those whose task, project, task list or notes match what's typed.
    private var shown: [AssignedTask] {
        items.filter { matchesFilter(typed, fields: $0.item.filterFields + [$0.list].compactMap { $0 }) }
    }

    private struct ProjectGroup: Identifiable {
        let id: Int
        let name: String
        var tasks: [AssignedTask]
    }

    var body: some View {
        Page {
            ForEach(Self.byProject(shown)) { group in
                Section {
                    ForEach(group.tasks) { task in
                        WorkRow(item: task.item, detail: task.list, due: task.due, startButton: true) {
                            Task { await store.start(task.item) }
                        }
                        RowDivider()
                    }
                } header: {
                    SectionHeader(group.name)
                }
            }
        }
        .overlay {
            if items.isEmpty && loading {
                ProgressView().controlSize(.small) // as on the other pages that load
            } else if items.isEmpty && failed {
                LoadFailed { Task { await load() } }
            } else if items.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("Nothing assigned to you here."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: typed)
            }
        }
        // Switching filter crossfades the list rather than swapping it in one frame.
        .animation(.easeOut(duration: 0.2), value: items.map(\.id))
        .navigationTitle("My Tasks")
        .navigationSubtitle(typed.isEmpty ? subtitle : "\(shown.count) of \(items.count) task\(items.count == 1 ? "" : "s")")
        .entryFilter($query, focused: $filterFocused, prompt: "Filter by task, project or list")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(TeamworkClient.TaskFilter.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        // Also once the user ID arrives (right after launch or sign-in it can still be loading), and after a log
        // or ⌘R: a task marked complete while logging leaves the list.
        .task(id: "\(filter)|\(store.userId ?? 0)|\(store.logRevision)") { await load() }
    }

    private func load() async {
        loading = true
        let fetched = await store.myTasks(filter)
        guard !Task.isCancelled else { return }
        if let fetched {
            items = fetched
            shownFilter = filter
        } else if shownFilter != filter {
            items = []
        }
        // Without a user ID nothing was asked; the load runs again when it arrives.
        failed = fetched == nil && store.userId != nil
        loading = false
    }

    /// "13 tasks in 6 projects · 2 overdue"; the overdue count only where the filter doesn't already say so.
    private var subtitle: String {
        guard !items.isEmpty else { return "" }
        let projects = Set(items.map(\.item.projectId)).count
        var text = "\(items.count) task\(items.count == 1 ? "" : "s") in \(projects) project\(projects == 1 ? "" : "s")"
        let late = items.filter { $0.due.map { WorkRow.due($0).late } ?? false }.count
        if late > 0 && filter != .overdue { text += " · \(late) overdue" }
        return text
    }

    /// Projects in the order of their first task: Teamwork sorts by due date, so the most pressing project leads.
    private static func byProject(_ tasks: [AssignedTask]) -> [ProjectGroup] {
        var groups: [ProjectGroup] = []
        for task in tasks {
            if let index = groups.firstIndex(where: { $0.id == task.item.projectId }) {
                groups[index].tasks.append(task)
            } else {
                groups.append(ProjectGroup(id: task.item.projectId, name: task.item.projectName, tasks: [task]))
            }
        }
        return groups
    }
}
