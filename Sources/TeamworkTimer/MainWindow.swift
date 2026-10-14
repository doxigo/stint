import SwiftUI

/// Library + detail window for reviewing and editing. Daily start/stop lives in the menu bar.
struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(Store.Section.allCases, selection: $store.section) { section in
                Label(section.rawValue, systemImage: section.symbol)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("New Timer").font(.title2.bold())
            WorkPicker { item in
                dismiss()
                Task { await store.start(item) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 480)
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
                .listRowInsets(EdgeInsets()) // the row pads itself and tints edge to edge when running
        }
    }
}

extension View {
    /// On the List, not the ForEach: modifiers on a ForEach apply to every row.
    func timerSheet(_ sheet: Binding<TimerSheet?>) -> some View {
        self.sheet(item: sheet) { which in
            Group {
                switch which {
                case .log(let timer): LogView(timer: timer) { sheet.wrappedValue = nil }
                case .edit(let timer): EditTimerView(timer: timer) { sheet.wrappedValue = nil }
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }
}

struct TimersView: View {
    @Environment(Store.self) private var store
    @State private var sheet: TimerSheet?

    var body: some View {
        List { TimerList(sheet: $sheet) }
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

/// Logged time for a day or a week, grouped by day with totals.
struct EntriesView: View {
    @Environment(Store.self) private var store
    let span: Calendar.Component
    @State private var anchor = Date.now
    @State private var entries: [TimeEntry] = []
    @State private var loading = false
    @State private var sheet: TimerSheet?
    @State private var editingEntry: TimeEntry?
    @State private var deletingEntry: TimeEntry?
    @State private var loadedInterval: DateInterval?

    private var interval: DateInterval { Calendar.current.dateInterval(of: span, for: anchor)! }
    private var isCurrent: Bool { interval.contains(.now) }
    private var total: TimeInterval { TimeInterval(entries.reduce(0) { $0 + $1.minutes } * 60) }
    /// Working-day target × weekdays in view; nil without a target or on a weekend.
    private var target: TimeInterval? {
        guard let day = store.dayTarget else { return nil }
        let days = weekdays(in: interval)
        return days > 0 ? day * Double(days) : nil
    }

    private var days: [(day: Date, entries: [TimeEntry])] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.timeLogged ?? interval.start) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            if let target { // the numbers are in the subtitle
                ProgressView(value: min(total / target, 1))
                    .accessibilityLabel("Logged")
                    .accessibilityValue("\(total.spoken) of \(target.spoken)")
            }
            if isCurrent && !store.timers.isEmpty {
                Section("Timers") { TimerList(sheet: $sheet) }
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry, onEdit: { editingEntry = entry }, onDelete: { deletingEntry = entry })
                    }
                } header: {
                    HStack {
                        Text(group.day.formatted(.dateTime.weekday(.wide).month().day()))
                        Spacer()
                        let logged = TimeInterval(group.entries.reduce(0) { $0 + $1.minutes } * 60)
                        let dayGoal = store.dayTarget.flatMap { weekdays(in: DateInterval(start: group.day, duration: 86_400)) > 0 ? $0 : nil }
                        Text(dayGoal.map { "\(logged.hoursMinutes) of \($0.hoursMinutes)" } ?? logged.hoursMinutes).monospacedDigit()
                    }
                }
            }
        }
        .timerSheet($sheet)
        .sheet(item: $editingEntry) { entry in
            EditEntryView(entry: entry) { editingEntry = nil }
                .padding(20)
                .frame(width: 400)
        }
        .confirmationDialog("Delete this time entry?", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }),
                            presenting: deletingEntry) { entry in
            Button("Delete \(TimeInterval(entry.minutes * 60).hoursMinutes)", role: .destructive) {
                Task { await store.deleteEntry(entry) }
            }
        } message: { _ in
            Text("It's removed from Teamwork.")
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
                Button("Today") { anchor = .now }
                    .keyboardShortcut("t")
                    .disabled(isCurrent)
                    .help("Go to Today (⌘T)")
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .keyboardShortcut("]")
                    .help(span == .day ? "Next Day (⌘])" : "Next Week (⌘])")
            }
        }
        // Reload on navigation and after anything is logged (here or from the popover).
        .task(id: "\(interval.start.timeIntervalSince1970)|\(store.logRevision)|\(store.userId ?? 0)") {
            if loadedInterval != interval { entries = [] } // never show another day's rows under this title
            loadedInterval = interval
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
        anchor = Calendar.current.date(byAdding: span, value: direction, to: anchor) ?? anchor
    }

    private func load() async {
        loading = true
        if let fetched = await store.timeEntries(from: interval.start, to: interval.end.addingTimeInterval(-1)) {
            entries = fetched
        }
        loading = false
    }
}

struct EntryRow: View {
    @Environment(Store.self) private var store
    let entry: TimeEntry
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        let taskName = entry.taskId.flatMap(store.taskName)
        let projectName = entry.projectId.map(store.projectName) ?? "No project"
        let item = entry.projectId.map {
            WorkItem(projectId: $0, projectName: projectName, taskId: entry.taskId, taskName: taskName,
                     description: entry.description, billable: entry.billable)
        }
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(taskName ?? projectName).lineLimit(1)
                Text([taskName == nil ? nil : projectName, entry.description.isEmpty ? nil : entry.description]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if entry.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Locked") }
            if entry.billable { Image(systemName: "dollarsign.circle").foregroundStyle(.secondary).accessibilityLabel("Billable") }
            Text(TimeInterval(entry.minutes * 60).hoursMinutes).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            // Locked entries (approved or invoiced) can't be changed in Teamwork either.
            if let onEdit { Button("Edit…", action: onEdit).disabled(entry.locked) }
            if let item {
                Button("Start Timer Again") { Task { await store.start(item) } }
                Button(store.isPinned(item) ? "Unpin" : "Pin") { store.togglePin(item) }
            }
            if let url = store.webURL(projectId: entry.projectId, taskId: entry.taskId) {
                Link("Open in Teamwork", destination: url)
            }
            if let onDelete {
                Divider()
                Button("Delete…", role: .destructive, action: onDelete).disabled(entry.locked)
            }
        }
        .onTapGesture(count: 2) { if !entry.locked { onEdit?() } }
    }
}

struct PinnedView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            ForEach(store.pins) { item in
                WorkRow(item: item, showsPin: false) { Task { await store.start(item) } }
            }
            .onMove(perform: store.movePins)
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

    var body: some View {
        List(store.starred) { project in
            DisclosureGroup {
                ProjectTasks(project: project)
            } label: {
                Label(project.name, systemImage: "star.fill")
                    .contextMenu {
                        Button("Start Timer on Project") { Task { await store.start(WorkItem(project: project)) } }
                        Button("Pin Project") { store.togglePin(WorkItem(project: project)) }
                        Button("Unstar Project") { Task { await store.setStarred(project, false) } }
                    }
            }
        }
        .overlay {
            if store.starred.isEmpty {
                ContentUnavailableView("No Starred Projects", systemImage: "star",
                                       description: Text("Star projects in Teamwork and they appear here and first in every picker."))
            }
        }
        .navigationTitle("Starred Projects")
        .task { await store.loadStarred() }
    }
}

/// A project's tasks, loaded when its row is expanded.
struct ProjectTasks: View {
    @Environment(Store.self) private var store
    let project: Project
    @State private var items: [WorkItem]?

    var body: some View {
        Group {
            if let items {
                ForEach(items) { item in WorkRow(item: item) { Task { await store.start(item) } } }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task { items = await store.search("", in: project) }
    }
}

struct MyTasksView: View {
    @Environment(Store.self) private var store
    @AppStorage("myTasksFilter") private var filter = TeamworkClient.TaskFilter.today
    @State private var items: [WorkItem] = []
    @State private var loading = false

    var body: some View {
        List(items) { item in
            WorkRow(item: item) { Task { await store.start(item) } }
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
