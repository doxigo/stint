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
    @Environment(Store.self) private var store
    @Binding var sheet: TimerSheet?

    var body: some View {
        ForEach(store.timers) { timer in
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

    var body: some View {
        Page { TimerList(sheet: $sheet) }
            .timerSheet($sheet)
            .overlay {
                if store.timers.isEmpty {
                    ContentUnavailableView("No Timers", systemImage: "timer",
                                           description: Text("Start one with ⌘N or from the menu bar, or drop a Teamwork task link here. Timers started on the web show up too."))
                }
            }
            .navigationTitle("Timers")
            .navigationSubtitle(store.timers.isEmpty ? "" : "\(store.timers.count) timer\(store.timers.count == 1 ? "" : "s")")
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

/// Logged time for a day (with the popover's week strip) or a week, grouped by day with totals.
struct EntriesView: View {
    @Environment(Store.self) private var store
    let span: Calendar.Component
    @State private var anchor = Calendar.current.startOfDay(for: .now)
    @State private var sheet: TimerSheet?
    @State private var editingEntry: TimeEntry?
    @State private var position = ScrollPosition(idType: Date.self)

    private var calendar: Calendar { .current }
    private var interval: DateInterval { calendar.dateInterval(of: span, for: anchor)! }
    private var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: anchor)! }
    private var isCurrent: Bool { interval.contains(.now) }
    /// nil until the week has loaded once (then cached in the store).
    private var weekEntries: [TimeEntry]? { store.weeks[week.start] }
    private var entries: [TimeEntry] { (weekEntries ?? []).filter { $0.timeLogged.map(interval.contains) ?? false } }
    private var total: TimeInterval { TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60) }
    /// Working hours in view; nil on days off.
    private var target: TimeInterval? { store.target(in: interval) }
    /// No entries and, in the current period, no timers either.
    private var isEmpty: Bool { entries.isEmpty && !(isCurrent && !store.timers.isEmpty) }

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timeLogged ?? interval.start) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { ($0.timeLogged ?? .distantPast) < ($1.timeLogged ?? .distantPast) }) }
    }

    /// Per-day totals for the week strip, today's timers included (as in the popover).
    private var dayTotals: [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for entry in weekEntries ?? [] {
            guard let logged = entry.timeLogged else { continue }
            totals[calendar.startOfDay(for: logged), default: 0] += TimeInterval(entry.minutes * 60)
        }
        for timer in store.timers { totals[calendar.startOfDay(for: .now), default: 0] += store.elapsed(timer) }
        return totals
    }

    var body: some View {
        Page {
            if span == .weekOfYear {
                if weekEntries != nil && !isEmpty {
                    WeekChart(week: interval, entries: entries) { day in
                        withAnimation { position.scrollTo(id: day, anchor: .top) }
                    }
                }
            } else if let target { // the numbers are in the subtitle
                ProgressView(value: min(total / target, 1))
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.m)
                    .accessibilityLabel("Logged")
                    .accessibilityValue("\(total.spoken) of \(target.spoken)")
            }
            if isCurrent && !store.timers.isEmpty {
                Section { TimerList(sheet: $sheet) } header: { SectionHeader("Timers") }
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
                    SectionHeader(group.day.formatted(.dateTime.weekday(.wide).month().day()),
                                  trailing: goal.map { "\(logged.hoursMinutes) / \($0.hoursMinutes)" } ?? logged.hoursMinutes)
                }
            }
        }
        .scrollPosition($position) // the week chart scrolls to a clicked day
        .safeAreaInset(edge: .top, spacing: 0) {
            if span == .day {
                VStack(spacing: 0) {
                    WeekStrip(week: week, selected: $anchor, totals: dayTotals)
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
                ProgressView().controlSize(.small)
            } else if isEmpty {
                ContentUnavailableView("Nothing Logged", systemImage: "clock", description: Text("Time you log shows up here."))
            }
        }
        // A week that arrives from the network fades in over the spinner. Leaving a week (⌘[ ⌘]) and cached
        // weeks stay instant: keyboard steps shouldn't wait on a fade.
        .animation(weekEntries == nil ? nil : .easeOut(duration: 0.2), value: weekEntries == nil)
        .navigationTitle(title)
        .navigationSubtitle(target.map { "Logged \(total.hoursMinutes) of \($0.hoursMinutes)" } ?? "Logged \(total.hoursMinutes)")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                    .keyboardShortcut("[")
                    .help(span == .day ? "Previous Day (⌘[)" : "Previous Week (⌘[)")
                Button("Today") { anchor = calendar.startOfDay(for: .now) }
                    .keyboardShortcut("t")
                    .disabled(isCurrent)
                    .help("Go to Today (⌘T)")
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .keyboardShortcut("]")
                    .help(span == .day ? "Next Day (⌘])" : "Next Week (⌘])")
            }
        }
        // Revalidates the (cached) week on week change, after anything is logged (here or from the popover),
        // and once the user ID arrives.
        .task(id: "\(week.start.timeIntervalSince1970)|\(store.logRevision)|\(store.userId ?? 0)") {
            await store.loadWeek(containing: anchor)
        }
        .refreshable { await store.loadWeek(containing: anchor) }
        // Back from the browser: entries edited on the web show up.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.loadWeek(containing: anchor) }
        }
    }

    private var title: String {
        if span == .day { return isCurrent ? "Today" : anchor.formatted(.dateTime.weekday(.wide).month().day()) }
        if isCurrent { return "This Week" }
        return "Week of \(interval.start.formatted(.dateTime.month().day()))"
    }

    private func step(_ direction: Int) {
        anchor = calendar.date(byAdding: span, value: direction, to: anchor) ?? anchor
    }

    private func start(_ item: WorkItem) {
        anchor = calendar.startOfDay(for: .now)
        Task { await store.start(item) }
    }
}

struct PinnedView: View {
    @Environment(Store.self) private var store
    @State private var logging: WorkItem?

    var body: some View {
        Page {
            ForEach(Array(store.pins.enumerated()), id: \.element.id) { index, item in
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
            }
        }
        .sheet(item: $logging) { item in
            LogWorkView(item: item) { logging = nil }
                .frame(width: 440)
        }
        .navigationTitle("Pinned")
        .navigationSubtitle("Drag to reorder. The first nine start with ⌘1–⌘9 in the menu bar.")
    }
}

struct StarredView: View {
    @Environment(Store.self) private var store
    @State private var path: [Project] = []

    var body: some View {
        NavigationStack(path: $path) {
            Page {
                ForEach(store.starred) { project in
                    ProjectRow(project: project, open: { path.append(project) },
                               start: { Task { await store.start(WorkItem(project: project)) } })
                    RowDivider()
                }
            }
            .overlay {
                if store.starred.isEmpty {
                    ContentUnavailableView("No Starred Projects", systemImage: "star",
                                           description: Text("Star projects in Teamwork and they appear here and first in every picker."))
                }
            }
            .navigationTitle("Starred Projects")
            .navigationDestination(for: Project.self) { ProjectTasks(project: $0) }
        }
        .task { await store.loadStarred() }
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

struct MyTasksView: View {
    @Environment(Store.self) private var store
    @AppStorage("myTasksFilter") private var filter = TeamworkClient.TaskFilter.today
    @State private var items: [WorkItem] = []
    /// True from the start: false showed "No Tasks" for a frame before the first load began.
    @State private var loading = true

    var body: some View {
        Page {
            ForEach(items) { item in
                WorkRow(item: item, startButton: true) { Task { await store.start(item) } }
                RowDivider()
            }
        }
        .overlay {
            if items.isEmpty && loading {
                ProgressView().controlSize(.small) // as on the other pages that load
            } else if items.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("Nothing assigned to you here."))
            }
        }
        // Switching filter crossfades the list rather than swapping it in one frame.
        .animation(.easeOut(duration: 0.2), value: items.map(\.id))
        .navigationTitle("My Tasks")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(TeamworkClient.TaskFilter.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        // Also once the user ID arrives: right after launch or sign-in it can still be loading.
        .task(id: "\(filter)|\(store.userId ?? 0)") {
            loading = true
            if let fetched = await store.myTasks(filter) { items = fetched }
            loading = false
        }
    }
}
