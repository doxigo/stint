import SwiftUI

/// What the status item shows for the current timer (Settings › General › Menu Bar).
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case taskAndTime = "Task and time"
    case time = "Time"
    case icon = "Icon only"
    var id: Self { self }
}

/// Status item, the app's main timer display (as in Harvest): live time of the current timer,
/// including one started on the web. Icon only when nothing is tracked.
struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarStyle") private var style = MenuBarStyle.time
    @AppStorage("menuBarSeconds") private var showsSeconds = false

    var body: some View {
        content
            // The label exists from launch, so it hands the store a way to open the main window
            // (used by the end-of-day notification's "Log All…").
            .onAppear { store.openMainWindow = { openWindow(id: "main") } }
    }

    @ViewBuilder private var content: some View {
        if let timer = store.activeTimer {
            // A status item shows one image and one text, so task and time go in a single string.
            // Plain text on the store's clock; see `Store.menuBarNow` for why not TimerText.
            let elapsed = store.elapsed(timer, at: store.menuBarNow)
            let time = showsSeconds ? elapsed.clock : elapsed.hoursMinutes
            HStack(spacing: 4) {
                // Shape, not just colour, tells running from paused.
                Image(systemName: timer.running ? "play.fill" : "pause.fill")
                switch style {
                // Leading space: the status item ignores HStack spacing between its image and title.
                case .taskAndTime: Text(" \(Self.shortened(store.title(of: timer)))  \(time)").monospacedDigit()
                case .time: Text(" \(time)").monospacedDigit()
                case .icon: EmptyView()
                }
            }
        } else {
            Image(systemName: "timer")
        }
    }

    /// Keeps the status item from crowding out other menu bar items.
    static func shortened(_ title: String) -> String {
        title.count > 24 ? title.prefix(23) + "…" : title
    }
}

/// Count-up clock driven by the system, for windows (popover, main window, mini timer).
/// Not for the menu bar label, where time-based views hang the app.
struct TimerText: View {
    @Environment(Store.self) private var store
    let timer: TWTimer

    var body: some View {
        Group {
            if timer.running {
                Text(timerInterval: store.clockStart(timer)...Date.distantFuture, countsDown: false)
            } else {
                Text(store.elapsed(timer).clock)
            }
        }
        .monospacedDigit()
    }
}

/// Search plus Pinned / Recent / Starred Projects; used by the popover and the New Timer sheet.
struct WorkPicker: View {
    @Environment(Store.self) private var store
    var maxHeight: CGFloat?
    let start: (WorkItem) -> Void
    @State private var query = ""
    @State private var scope: Project?
    @State private var results: [WorkItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Spotlight-style field: a magnifying glass reads as "search to start", like menu bar search fields.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(scope.map { "Search \($0.name)…" } ?? "Start a timer…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { if let first = results.first { pick(first) } }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 1)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 9))
            ScrollView { list }
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: maxHeight != nil)
        }
        .task(id: "\(scope?.id ?? 0)|\(query)") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // A pasted task link resolves to that task.
            if taskID(fromLink: query) != nil {
                results = await store.item(fromLink: query).map { [$0] } ?? []
            } else {
                results = await store.search(query, in: scope)
            }
        }
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: Space.xxs / 2) {
            if let scope {
                Button { self.scope = nil; query = "" } label: {
                    Label(scope.name, systemImage: "chevron.left").font(.headline)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                rows(results)
            } else if !query.isEmpty {
                rows(results)
                if results.isEmpty { Text("No matches").foregroundStyle(.secondary).padding(8) }
            } else {
                if !store.pins.isEmpty {
                    SectionHeader("Pinned")
                    rows(store.pins, numbered: true)
                }
                let running = store.timers.compactMap(store.workItem(for:))
                let fresh = { (item: WorkItem) in !store.isPinned(item) && !running.contains { $0.sameTarget(as: item) } }
                let due = store.dueToday.filter(fresh)
                if !due.isEmpty {
                    SectionHeader("Due Today")
                    rows(due)
                }
                let recents = store.recents.filter { item in fresh(item) && !due.contains { $0.sameTarget(as: item) } }
                if !recents.isEmpty {
                    SectionHeader("Recent")
                    rows(recents)
                }
                if !store.starred.isEmpty {
                    SectionHeader("Starred Projects")
                    ForEach(store.starred) { project in
                        Button { scope = project } label: {
                            HStack {
                                Text(project.name).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(RowStyle())
                        .accessibilityHint("Shows the project's tasks")
                        .contextMenu {
                            Button("Start Timer on Project") { pick(WorkItem(project: project)) }
                            Button("Pin Project") { store.togglePin(WorkItem(project: project)) }
                            Button("Unstar Project") { Task { await store.setStarred(project, false) } }
                        }
                    }
                }
                if store.pins.isEmpty && due.isEmpty && recents.isEmpty && store.starred.isEmpty {
                    Text("Search for a project or task, or paste a task link, to start a timer. Pin it to start it in one click next time.")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
    }

    private func rows(_ items: [WorkItem], numbered: Bool = false) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            WorkRow(item: item, shortcut: numbered && index < 9 ? index + 1 : nil) { pick(item) }
        }
    }

    private func pick(_ item: WorkItem) {
        query = ""
        scope = nil
        start(item)
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.s)
            .padding(.top, Space.m).padding(.bottom, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A startable project/task. ⌘1–⌘9 start the first nine pins.
struct WorkRow: View {
    @Environment(Store.self) private var store
    let item: WorkItem
    var shortcut: Int?
    /// Off inside the pinned list itself, where every row is pinned.
    var showsPin = true
    let start: () -> Void
    @State private var hovering = false

    var body: some View {
        let pinned = store.isPinned(item)
        Button(action: start) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let shortcut {
                    Text("⌘\(shortcut)").font(.caption).foregroundStyle(.tertiary)
                } else if pinned && showsPin {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                }
                // Quiet lists: the start affordance appears on hover; the whole row is the button.
                Image(systemName: "play.fill")
                    .foregroundStyle(.tint)
                    .opacity(hovering ? 1 : 0)
            }
        }
        .buttonStyle(RowStyle())
        .onHover { hovering = $0 }
        .keyboardShortcut(shortcut.map { KeyboardShortcut(KeyEquivalent(Character(String($0))), modifiers: .command) })
        .contextMenu {
            Button("Start Timer", action: start)
            Button(pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            if let url = store.webURL(projectId: item.projectId, taskId: item.taskId) {
                Link("Open in Teamwork", destination: url)
            }
        }
        .accessibilityLabel([item.title, item.subtitle, pinned ? "pinned" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Starts a timer")
        .accessibilityAction(named: pinned ? "Unpin" : "Pin") { store.togglePin(item) }
    }
}

/// Harvest-style timer row: task (up to two lines), project and notes; time and one Start/Pause button.
/// Log and ⋯ appear on hover; every action is also in the context menu and VoiceOver actions.
struct TimerRow: View {
    @Environment(Store.self) private var store
    let timer: TWTimer
    let onLog: () -> Void
    var onEdit: (() -> Void)?
    @State private var confirmingDiscard = false
    @State private var hovering = false

    var body: some View {
        if confirmingDiscard { discardConfirmation } else { row }
    }

    /// Inline rather than a dialog: dialogs attached to the menu-bar window can close it and lose the action.
    private var discardConfirmation: some View {
        HStack {
            Label("Discard \(store.elapsed(timer).hoursMinutes) without logging?", systemImage: "trash")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { confirmingDiscard = false }
                .keyboardShortcut(.cancelAction)
            Button("Discard", role: .destructive) {
                confirmingDiscard = false
                Task { await store.discard(timer) }
            }
        }
        .padding(.vertical, 4)
    }

    private var row: some View {
        let title = store.title(of: timer)
        let project = store.subtitle(of: timer)
        let notes = timer.description.isEmpty || timer.description == title ? nil : timer.description
        let elapsed = store.elapsed(timer, at: store.menuBarNow)
        return HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).fontWeight(.semibold).lineLimit(2)
                if let project { Text(project).foregroundStyle(.secondary).lineLimit(1) }
                if let notes { Text(notes).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    if timer.running { LiveDot() }
                    Text(elapsed.hoursMinutes)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(timer.running ? .primary : .secondary)
                        .accessibilityLabel("\(timer.running ? "Running" : "Paused"), \(elapsed.spoken)")
                    startPause(title)
                }
                HStack(spacing: Space.m) {
                    Button("Log…", action: onLog).help("Stop and log time")
                    actionsMenu
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .background(timer.running ? Brand.purple.opacity(0.07) : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(timer.running ? "Pause" : "Start") { Task { await store.toggle(timer) } }
            Button("Log…", action: onLog)
            menuItems
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Log") { onLog() }
    }

    /// The row's one primary control. Text plus a filled/bordered style, so state isn't colour alone.
    @ViewBuilder private func startPause(_ title: String) -> some View {
        if timer.running {
            Button { Task { await store.toggle(timer) } } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.borderedProminent)
                .tint(Brand.purpleFill)
                .accessibilityLabel("Pause \(title)")
        } else {
            Button { Task { await store.toggle(timer) } } label: { Label("Start", systemImage: "clock") }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start \(title)")
        }
    }

    private var actionsMenu: some View {
        Menu { menuItems } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
    }

    @ViewBuilder private var menuItems: some View {
        if let onEdit { Button("Edit Task or Notes…", action: onEdit) }
        if let item = store.workItem(for: timer) {
            Button(store.isPinned(item) ? "Unpin" : "Pin") { store.togglePin(item) }
        }
        if let url = store.webURL(projectId: timer.projectId, taskId: timer.taskId) {
            Link("Open in Teamwork", destination: url)
        }
        Divider()
        Button("Discard Timer…", role: .destructive) { confirmingDiscard = true }
    }
}

/// Confirms a log: editable duration ("1:30", "1.5h", "90m"), pre-rounded per Settings,
/// description, billable, mark task complete.
struct LogView: View {
    @Environment(Store.self) private var store
    @AppStorage("rounding") private var rounding = Rounding.off
    @AppStorage("roundingStep") private var roundingStep = 15
    let timer: TWTimer
    let done: () -> Void
    @State private var duration = ""
    /// Tracked time when the form opened, before rounding.
    @State private var exactDuration = ""
    @State private var description = ""
    @State private var billable = false
    @State private var markComplete = false
    @State private var saving = false

    var body: some View {
        let seconds = parseDuration(duration)
        VStack(alignment: .leading, spacing: 10) {
            Text("Log Time").font(.title2.bold())
            VStack(alignment: .leading, spacing: 1) {
                Text(store.title(of: timer))
                if let subtitle = store.subtitle(of: timer) { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            LabeledContent("Duration") {
                TextField("Duration", text: $duration, prompt: Text("1:30, 1.5h, 90m"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .monospacedDigit()
            }
            if seconds != nil, duration != exactDuration {
                Text("Tracked \(exactDuration)\(rounding != .off ? " · \(rounding.rawValue.lowercased()) to \(roundingStep) min" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if seconds == nil {
                Label("Enter a duration like 1:30, 1.5h or 90m.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let seconds, seconds < 60 {
                Label("Teamwork logs whole minutes; enter at least 1 minute.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Toggle("Billable", isOn: $billable)
            if timer.taskId != nil { Toggle("Mark task complete", isOn: $markComplete) }
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Log \(seconds.map(\.hoursMinutes) ?? "")") {
                    guard let seconds else { return }
                    saving = true
                    Task {
                        // Unrounded, untouched field → let Teamwork log the live timer time ("complete").
                        if await store.log(timer, seconds: seconds, durationEdited: duration != exactDuration,
                                           description: description, billable: billable, markTaskComplete: markComplete) { done() }
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .tint(Brand.purpleFill) // filled default button: fixed purple keeps white text readable in Dark Mode
                .disabled(saving || (seconds ?? 0) < 60)
            }
        }
        .onAppear {
            let tracked = store.elapsed(timer)
            exactDuration = tracked.hoursMinutes
            duration = rounding.apply(tracked, step: roundingStep).hoursMinutes
            description = timer.description
            billable = timer.billable
        }
    }
}

/// Menu-like rows: full-width hit target with a hover highlight, as in native menus.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .background(.quaternary.opacity(hovering || configuration.isPressed ? 1 : 0), in: .rect(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}
