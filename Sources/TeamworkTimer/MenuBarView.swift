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

/// Always-h:mm:ss clock ("0:37:18"), refreshed by the store's one-second ticker while a timer runs.
/// The system timer text drops the hour below 60 minutes ("37:18"), which reads like 37 hours.
struct TimerText: View {
    @Environment(Store.self) private var store
    let timer: TWTimer

    var body: some View {
        Text(store.elapsed(timer, at: store.menuBarNow).clock).monospacedDigit()
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
        VStack(spacing: 0) {
            // Spotlight-style field: a magnifying glass reads as "search to start", like menu bar search fields.
            HStack(spacing: Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(scope.map { "Search \($0.name)…" } ?? "Search tasks and projects, or paste a link", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { if let first = results.first { pick(first) } }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 2)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 9))
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            Divider()
            ScrollView { list.padding(.bottom, Space.s) }
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
        VStack(alignment: .leading, spacing: 0) {
            if let scope {
                Button { self.scope = nil; query = "" } label: {
                    Label(scope.name, systemImage: "chevron.left").fontWeight(.semibold)
                }
                .buttonStyle(RowStyle())
                .accessibilityHint("Back to all projects")
                rows(results, showsProject: false)
            } else if !query.isEmpty {
                rows(results)
                if results.isEmpty { emptyNote("No tasks or projects match “\(query)”.") }
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
                        ProjectRow(project: project, open: { scope = project }, start: { pick(WorkItem(project: project)) })
                    }
                }
                if store.pins.isEmpty && due.isEmpty && recents.isEmpty && store.starred.isEmpty {
                    emptyNote("Search for a task or project, or paste a Teamwork task link. Pin what you repeat to start it in one click next time.")
                }
            }
        }
    }

    private func rows(_ items: [WorkItem], numbered: Bool = false, showsProject: Bool = true) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            WorkRow(item: item, shortcut: numbered && index < 9 ? index + 1 : nil, showsProject: showsProject) { pick(item) }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
    }

    private func pick(_ item: WorkItem) {
        query = ""
        scope = nil
        start(item)
    }
}

/// A task or project title that opens it in Teamwork with one click. Quiet until hovered:
/// then it underlines, shows ↗ and the link cursor.
struct TitleLink: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let url: URL?
    var lineLimit = 2
    @State private var hovering = false
    @State private var lastOpened = Date.distantPast

    var body: some View {
        if let url {
            Button {
                // A double-click on the row shouldn't open two tabs.
                guard Date.now.timeIntervalSince(lastOpened) > 1 else { return }
                lastOpened = .now
                openURL(url)
            } label: {
                Text(hovering ? "\(title) \(Image(systemName: "arrow.up.right"))" : "\(title)")
                    .fontWeight(.semibold)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
                    .underline(hovering)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering = $0 }
            .help("Open in Teamwork")
            .accessibilityLabel("\(title), open in Teamwork")
            .accessibilityAddTraits(.isLink)
        } else {
            Text(title).fontWeight(.semibold).lineLimit(lineLimit)
        }
    }
}

/// Group label in small caps, aligned with row text; optional trailing value (e.g. a day total).
struct SectionHeader: View {
    let title: String
    var trailing: String?
    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased()).tracking(0.6)
            Spacer()
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xs)
        .background(.background) // opaque when pinned over scrolling rows in the window
        .accessibilityAddTraits(.isHeader)
    }
}

/// A starred project that opens its task list; start, pin and unstar from the context menu.
struct ProjectRow: View {
    @Environment(Store.self) private var store
    let project: Project
    let open: () -> Void
    let start: () -> Void

    var body: some View {
        let item = WorkItem(project: project)
        Button(action: open) {
            HStack {
                Text(project.name).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(RowStyle())
        .accessibilityHint("Shows the project's tasks")
        .contextMenu {
            Button("Start Timer on Project", action: start)
            Button(store.isPinned(item) ? "Unpin Project" : "Pin Project") { store.togglePin(item) }
            Button("Unstar Project") { Task { await store.setStarred(project, false) } }
        }
    }
}

/// A startable project/task. ⌘1–⌘9 start the first nine pins.
struct WorkRow: View {
    @Environment(Store.self) private var store
    let item: WorkItem
    var shortcut: Int?
    /// Off inside the pinned list itself, where every row is pinned.
    var showsPin = true
    /// Off inside a project's own task list.
    var showsProject = true
    let start: () -> Void
    @State private var hovering = false

    var body: some View {
        let pinned = store.isPinned(item)
        Button(action: start) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    Text(item.title).lineLimit(2).multilineTextAlignment(.leading)
                    if showsProject, let subtitle = item.subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s)
                if let shortcut {
                    Text("⌘\(shortcut)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
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
                TitleLink(title: title, url: store.webURL(projectId: timer.projectId, taskId: timer.taskId))
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

/// Full-width list rows, padded like the day list, with a faint brand-purple hover wash.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .background(Brand.purple.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
                .onHover { hovering = $0 }
        }
    }
}
