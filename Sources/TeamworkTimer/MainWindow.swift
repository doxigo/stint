import SwiftUI

/// Library + detail window for reviewing and editing. Daily start/stop lives in the menu bar.
struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            // Our own selection: List(selection:) paints the system accent (blue), which the app can't
            // change without an Xcode-built asset catalog. ⌘1–⌘6 (View menu) select sections from the keyboard.
            List(Store.Section.allCases) { section in
                let selected = (store.section ?? .timers) == section
                Button { store.section = section } label: {
                    Label {
                        Text(section.rawValue).fontWeight(selected ? .semibold : .regular)
                    } icon: {
                        Image(systemName: section.symbol).foregroundStyle(Brand.purple)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xs - 2)
                    .background(Brand.purple.opacity(selected ? 0.14 : 0), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                if !store.isSignedIn {
                    ContentUnavailableView("Not Signed In", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("Sign in from Settings (⌘,) to see your timers."))
                } else {
                    switch store.section ?? .timers {
                    case .timers: TimersView()
                    case .today: EntriesView(span: .day)
                    case .week: EntriesView(span: .weekOfYear)
                    case .pinned: PinnedView()
                    case .starred: StarredView()
                    case .tasks: MyTasksView()
                    }
                }
            }
            .frame(minWidth: 420)
            .safeAreaInset(edge: .bottom) {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
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
                .padding(20)
                .frame(width: 460)
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
    @State private var weekEntries: [TimeEntry] = []
    @State private var loading = false
    @State private var sheet: TimerSheet?
    @State private var editingEntry: TimeEntry?
    @State private var loadedWeek: DateInterval?

    private var calendar: Calendar { .current }
    private var interval: DateInterval { calendar.dateInterval(of: span, for: anchor)! }
    private var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: anchor)! }
    private var isCurrent: Bool { interval.contains(.now) }
    private var entries: [TimeEntry] { weekEntries.filter { $0.timeLogged.map(interval.contains) ?? false } }
    private var total: TimeInterval { TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60) }
    /// Working-day target × weekdays in view; nil without a target or on a weekend.
    private var target: TimeInterval? {
        guard let day = store.dayTarget else { return nil }
        let days = weekdays(in: interval)
        return days > 0 ? day * Double(days) : nil
    }

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timeLogged ?? interval.start) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { ($0.timeLogged ?? .distantPast) < ($1.timeLogged ?? .distantPast) }) }
    }

    /// Per-day totals for the week strip, today's timers included (as in the popover).
    private var dayTotals: [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for entry in weekEntries {
            guard let logged = entry.timeLogged else { continue }
            totals[calendar.startOfDay(for: logged), default: 0] += TimeInterval(entry.minutes * 60)
        }
        for timer in store.timers { totals[calendar.startOfDay(for: .now), default: 0] += store.elapsed(timer) }
        return totals
    }

    var body: some View {
        Page {
            if let target { // the numbers are in the subtitle
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
                        DayEntryRow(entry: entry) { editingEntry = entry }
                        RowDivider()
                    }
                } header: {
                    let logged = TimeInterval(group.entries.reduce(0) { $0 + $1.minutes } * 60)
                    let goal = store.dayTarget.flatMap { weekdays(in: DateInterval(start: group.day, duration: 86_400)) > 0 ? $0 : nil }
                    SectionHeader(group.day.formatted(.dateTime.weekday(.wide).month().day()),
                                  trailing: goal.map { "\(logged.hoursMinutes) / \($0.hoursMinutes)" } ?? logged.hoursMinutes)
                }
            }
        }
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
            if entries.isEmpty && !loading && !(isCurrent && !store.timers.isEmpty) {
                ContentUnavailableView("Nothing Logged", systemImage: "clock", description: Text("Time you log shows up here."))
            }
        }
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
        // Reload on week change, after anything is logged (here or from the popover), and once the user ID arrives.
        .task(id: "\(week.start.timeIntervalSince1970)|\(store.logRevision)|\(store.userId ?? 0)") {
            if loadedWeek != week { weekEntries = [] } // never show another week's rows under this title
            loadedWeek = week
            await load()
        }
        .refreshable { await load() }
    }

    private var title: String {
        if span == .day { return isCurrent ? "Today" : anchor.formatted(.dateTime.weekday(.wide).month().day()) }
        if isCurrent { return "This Week" }
        return "Week of \(interval.start.formatted(.dateTime.month().day()))"
    }

    private func step(_ direction: Int) {
        anchor = calendar.date(byAdding: span, value: direction, to: anchor) ?? anchor
    }

    private func load() async {
        loading = true
        if let fetched = await store.timeEntries(from: week.start, to: week.end.addingTimeInterval(-1)) {
            weekEntries = fetched
        }
        loading = false
    }
}

struct PinnedView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Page {
            ForEach(Array(store.pins.enumerated()), id: \.element.id) { index, item in
                WorkRow(item: item, showsPin: false) { Task { await store.start(item) } }
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
            WorkRow(item: item, showsProject: false) { Task { await store.start(item) } }
            RowDivider()
        }
    }
}

struct MyTasksView: View {
    @Environment(Store.self) private var store
    @AppStorage("myTasksFilter") private var filter = TeamworkClient.TaskFilter.today
    @State private var items: [WorkItem] = []
    @State private var loading = false

    var body: some View {
        Page {
            ForEach(items) { item in
                WorkRow(item: item) { Task { await store.start(item) } }
                RowDivider()
            }
        }
        .overlay {
            if items.isEmpty && !loading {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("Nothing assigned to you here."))
            }
        }
        .navigationTitle("My Tasks")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(TeamworkClient.TaskFilter.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .task(id: filter) {
            loading = true
            if let fetched = await store.myTasks(filter) { items = fetched }
            loading = false
        }
    }
}
