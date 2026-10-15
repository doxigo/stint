import SwiftUI

/// What the status item shows for the current timer (Settings › General › Menu Bar).
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case taskAndTime = "Task and time"
    case time = "Time"
    case badge = "Time badge"
    case icon = "Icon only"
    var id: Self { self }
}

/// Harvest-style badge: a play/pause segment and the time in one rounded pill. Drawn as a template
/// image, so the menu bar tints it for light and dark wallpapers; while running its segment can take
/// the brand colour instead, as Harvest's turns orange. Every style takes that running look; only the
/// Time badge keeps a pill otherwise.
@MainActor enum MenuBarBadge {
    private static let segment: CGFloat = 18
    private static var cached: (running: Bool, highlighted: Bool, text: String, image: NSImage)?

    /// The pill for `style` showing `text` (empty: the glyph alone, in a square), or nil where the
    /// style shows the plain glyph and title. `highlight` is the "Highlight while running" setting.
    static func image(_ style: MenuBarStyle, running: Bool, highlight: Bool, text: String) -> NSImage? {
        let highlighted = running && highlight
        guard style == .badge || highlighted else { return nil }
        if let cached, cached.running == running, cached.highlighted == highlighted, cached.text == text {
            return cached.image
        }
        let ink = highlighted ? NSColor.white : .black
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink,
        ])
        let glyph = NSImage(systemSymbolName: running ? "pause.fill" : "play.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 8, weight: .black).applying(.init(paletteColors: [ink])))!
        let height: CGFloat = 18, padding: CGFloat = 6
        let labelSize = label.size()
        let size = NSSize(width: text.isEmpty ? segment : segment + padding + ceil(labelSize.width) + padding, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            // Two tones, as in Harvest: the glyph segment a step stronger than the time segment.
            if highlighted {
                // As in Harvest, only the play/pause segment takes the colour; the time sits on the header's slate.
                NSColor(Brand.slate).setFill()
                rect.fill()
                NSColor(Brand.purpleFill).setFill()
                NSRect(x: 0, y: 0, width: segment, height: height).fill()
            } else {
                NSColor.black.withAlphaComponent(0.32).setFill()
                NSRect(x: 0, y: 0, width: segment, height: height).fill()
                NSColor.black.withAlphaComponent(0.16).setFill()
                NSRect(x: segment, y: 0, width: size.width - segment, height: height).fill()
            }
            glyph.draw(in: NSRect(x: (segment - glyph.size.width) / 2, y: (height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height))
            label.draw(at: NSPoint(x: segment + padding, y: (height - labelSize.height) / 2))
            return true
        }
        image.isTemplate = !highlighted
        cached = (running, highlighted, text, image)
        return image
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

/// A startable project/task. ⌘1–⌘9 start the first nine pins. The title opens it in Teamwork, as on the day rows.
/// In pickers (the popover) the rest of the row starts it; in the window's lists (`startButton`) a Start button
/// does, like the popover's day rows, so a stray click or double-click never starts anything.
/// With `log`, a Log control (a button beside Start, or an icon on hover in pickers) logs time without a timer.
struct WorkRow: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let item: WorkItem
    var shortcut: Int?
    /// Off inside the pinned list itself, where every row is pinned.
    var showsPin = true
    /// Off inside a project's own task list.
    var showsProject = true
    var startButton = false
    var log: (() -> Void)?
    let start: () -> Void
    @State private var hovering = false

    var body: some View {
        let pinned = store.isPinned(item)
        let url = store.webURL(projectId: item.projectId, taskId: item.taskId)
        Group {
            if startButton {
                HStack(spacing: Space.s) {
                    labels(pinned: pinned, url: url)
                    startControl
                    // Last, so it lines up down the list whatever Start / Resume / Running takes.
                    if let log {
                        Button(action: log) { Label("Log", systemImage: "clock.badge.checkmark") }
                            .buttonStyle(.bordered)
                            .help("Log time without starting a timer")
                            .accessibilityLabel("Log time to \(item.title)")
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .accessibilityElement(children: .contain)
            } else {
                HStack(spacing: Space.s) {
                    labels(pinned: pinned, url: url)
                    // Quiet lists: the log and start affordances appear on hover, as on timer rows. Hidden also
                    // means out of the click order; VoiceOver reaches Log through the row's actions.
                    if let log {
                        Button(action: log) { Label("Log", systemImage: "clock.badge.checkmark") }
                            .buttonStyle(RowIconStyle())
                            .frame(width: 30)
                            .help("Log time without starting a timer")
                            .opacity(hovering ? 1 : 0)
                            .disabled(!hovering)
                            .animation(.easeOut(duration: 0.15), value: hovering)
                    }
                    Image(systemName: "play.fill")
                        .foregroundStyle(.tint)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                // The start button sits behind the row rather than around it, so the title link isn't nested in
                // a button. Everything but the link and Log lets clicks through to it.
                .background {
                    Button(action: start) { Color.clear }
                        .buttonStyle(RowStyle())
                        .keyboardShortcut(shortcut.map { KeyboardShortcut(KeyEquivalent(Character(String($0))), modifiers: .command) })
                }
                // On the row, not the start button behind it, so it stays on while the pointer is over Log.
                .onHover { hovering = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Starts a timer")
                .accessibilityAction { start() }
                .accessibilityActions {
                    if let log { Button("Log time to \(item.title)", action: log) }
                    if let url { Button("Open in Teamwork") { openURL(url) } }
                }
            }
        }
        .contextMenu {
            Button("Start Timer", action: start)
            if let log { Button("Log Time…", action: log) }
            Button(pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            if let url { Link("Open in Teamwork", destination: url) }
        }
        .accessibilityLabel([item.title, item.subtitle, pinned ? "pinned" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAction(named: pinned ? "Unpin" : "Pin") { store.togglePin(item) }
    }

    @ViewBuilder private func labels(pinned: Bool, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs / 2) {
            TitleLink(title: item.title, url: url).allowsHitTesting(url != nil)
            if showsProject, let subtitle = item.subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).allowsHitTesting(false)
            }
        }
        Spacer(minLength: Space.s)
        Group {
            if let shortcut {
                Text("⌘\(shortcut)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            } else if pinned && showsPin {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    /// Start, or Resume / Running when this work already has a timer (Teamwork allows one per task).
    @ViewBuilder private var startControl: some View {
        let timer = store.timer(for: item)
        if timer?.running == true {
            HStack(spacing: Space.xs) {
                LiveDot()
                Text("Running").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button(action: start) { Label(timer == nil ? "Start" : "Resume", systemImage: "clock") }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(timer == nil ? "Start" : "Resume") \(item.title)")
        }
    }
}

/// Harvest-style timer row: task (up to two lines), project and notes; time and one Start/Pause button.
/// Edit and Log icons appear under it on hover; every action is also in the context menu and VoiceOver actions.
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

    private var discardConfirmation: some View {
        ConfirmRow(question: "Discard this timer?",
                   detail: "\(store.title(of: timer)) · \(store.elapsed(timer).hoursMinutes) won't be logged",
                   action: "Discard", cancel: { confirmingDiscard = false }) {
            confirmingDiscard = false
            Task { await store.discard(timer) }
        }
    }

    private var row: some View {
        let title = store.title(of: timer)
        let project = store.subtitle(of: timer)
        let notes = timer.description.isEmpty || timer.description == title ? nil : timer.description
        return HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                TitleLink(title: title, url: store.webURL(projectId: timer.projectId, taskId: timer.taskId))
                if let project { Text(project).foregroundStyle(.secondary).lineLimit(1) }
                if let notes { Text(notes).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if timer.running { LiveDot() }
                ElapsedText(timer: timer)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(timer.running ? .primary : .secondary)
                // One column as wide as Start/Pause, so Edit and Log split exactly its width.
                VStack(spacing: Space.xs) {
                    startPause(title)
                    HStack(spacing: Space.xxs) {
                        if let onEdit {
                            Button(action: onEdit) { Label("Edit", systemImage: "square.and.pencil") }
                                .help("Edit task or notes")
                                .accessibilityLabel("Edit \(title)")
                        }
                        Button(action: onLog) { Label("Log", systemImage: "clock.badge.checkmark") }
                            .help("Stop and log time")
                            .accessibilityLabel("Log \(title)")
                    }
                    .buttonStyle(RowIconStyle())
                    // Space kept while hidden, so rows don't jump. Hidden also means out of the click and Tab
                    // order; VoiceOver reaches both through the row's actions.
                    .opacity(hovering ? 1 : 0)
                    .disabled(!hovering)
                    .accessibilityHidden(!hovering)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                }
                .fixedSize(horizontal: true, vertical: false)
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
        // The context menu alone isn't reliably reachable with VoiceOver.
        .accessibilityActions {
            if let onEdit { Button("Edit Task or Notes", action: onEdit) }
            if let item = store.workItem(for: timer) {
                Button(store.isPinned(item) ? "Unpin" : "Pin") { store.togglePin(item) }
            }
            Button("Discard Timer") { confirmingDiscard = true }
        }
    }

    /// The row's one primary control. Text plus a filled/bordered style, so state isn't colour alone.
    @ViewBuilder private func startPause(_ title: String) -> some View {
        if timer.running {
            Button { Task { await store.toggle(timer) } } label: { startPauseLabel(Label("Pause", systemImage: "pause.fill")) }
                .buttonStyle(.borderedProminent)
                .tint(Brand.purpleFill)
                .accessibilityLabel("Pause \(title)")
        } else {
            Button { Task { await store.toggle(timer) } } label: { startPauseLabel(Label("Start", systemImage: "clock")) }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start \(title)")
        }
    }

    /// Sized for the wider of Start and Pause, so the column keeps its width when the timer toggles.
    private func startPauseLabel(_ label: some View) -> some View {
        ZStack {
            Label("Start", systemImage: "clock").hidden()
            Label("Pause", systemImage: "pause.fill").hidden()
            label
        }
        .frame(maxWidth: .infinity)
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

/// A timer row's secondary icons: quiet grey at rest, brand purple under the pointer, deeper when pressed.
/// Each fills its share of the row, so a pair spans the Start/Pause button above it.
struct RowIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Icon(configuration: configuration) }

    private struct Icon: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            let active = hovering || configuration.isPressed
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(active ? AnyShapeStyle(Brand.purple) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(active ? AnyShapeStyle(Brand.purple.opacity(configuration.isPressed ? 0.2 : 0.12))
                                   : AnyShapeStyle(.quaternary.opacity(0.6)),
                            in: .rect(cornerRadius: 7, style: .continuous))
                .contentShape(.rect)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A timer's h:mm on the store's clock. A leaf, so each second re-renders this text rather than its row.
struct ElapsedText: View {
    @Environment(Store.self) private var store
    let timer: TWTimer

    var body: some View {
        let elapsed = store.elapsed(timer, at: store.menuBarNow)
        Text(elapsed.hoursMinutes)
            .accessibilityLabel("\(timer.running ? "Running" : "Paused"), \(elapsed.spoken)")
    }
}
